# frozen_string_literal: true

module ::DisifyEmailProtection
  module ExistingUserScan
    module_function

    STATE_KEY = "existing_user_scan"
    STATE_MUTEX_KEY = "disify-email-protection-existing-user-scan-state"
    NORMAL_BATCH_DELAY = 65.seconds
    STALE_AFTER = 10.minutes
    CHECKPOINT_EVERY = 10
    PROVIDER_RATE_LIMIT_RESERVE = 1
    REQUEST_ID_PATTERN = /\A[a-z0-9._:-]{1,128}\z/i
    JOB_TOKEN_PATTERN = /\A[0-9a-f]{16}\z/.freeze
    ACTIVE_STATUSES = %w[running waiting].freeze
    BLOCKING_STATUSES = %w[running waiting paused].freeze

    def start!(actor:, scan_mode: nil, request_id: nil)
      raise Discourse::InvalidAccess unless actor&.admin?
      raise Discourse::InvalidParameters.new(:scan) unless SiteSetting.disify_email_protection_manual_scan_enabled
      raise Discourse::InvalidParameters.new(:plugin_disabled) unless SiteSetting.disify_email_protection_enabled

      mode = scan_mode.to_s.presence || SiteSetting.disify_email_protection_manual_scan_full_email_mode.to_s
      raise Discourse::InvalidParameters.new(:scan_mode) unless %w[domain_only trusted_providers all].include?(mode)
      request_id = normalize_request_id(request_id)

      should_enqueue = false
      payload = with_state_lock do
        current = normalize_stale_without_lock!(raw_state)

        # A single confirmation can occasionally be submitted twice by the client/browser.
        # Treat an identical request id as the same start operation instead of failing the
        # second request after the first one has already moved the scan to `running`.
        next current if request_id.present? && current["start_request_id"] == request_id

        if BLOCKING_STATUSES.include?(current["status"])
          raise Discourse::InvalidParameters.new(:scan_already_running)
        end

        should_enqueue = true

        now = Time.zone.now
        scan_id = SecureRandom.hex(8)
        job_token = SecureRandom.hex(8)
        new_state = {
          "scan_id" => scan_id,
          "status" => "running",
          "mode" => mode,
          "started_at" => now.iso8601,
          "started_by_id" => actor.id,
          "start_request_id" => request_id,
          "last_activity_at" => now.iso8601,
          "next_run_at" => nil,
          "cursor" => 0,
          "processed" => 0,
          "flagged" => 0,
          "total" => User.real.where(staged: false).count,
          "last_error" => nil,
          "queued_job_token" => job_token,
          "active_job_token" => nil,
        }
        store(new_state)
        new_state
      end

      if should_enqueue
        begin
          Jobs.enqueue(
            Jobs::DisifyExistingUserScan,
            scan_id: payload["scan_id"],
            job_token: payload["queued_job_token"],
          )
        rescue StandardError
          pause_error_if_active!(
            payload["scan_id"],
            "enqueue_failed",
            queued_token: payload["queued_job_token"],
          )
          raise
        end
      end
      public_state(payload)
    end

    def resume!(actor:)
      raise Discourse::InvalidAccess unless actor&.admin?
      raise Discourse::InvalidParameters.new(:plugin_disabled) unless SiteSetting.disify_email_protection_enabled

      current = with_state_lock do
        scan = normalize_stale_without_lock!(raw_state)
        raise Discourse::InvalidParameters.new(:scan) unless scan["status"] == "paused"

        scan["status"] = "running"
        scan["last_error"] = nil
        scan["paused_at"] = nil
        scan["last_activity_at"] = Time.zone.now.iso8601
        scan["next_run_at"] = nil
        scan["queued_job_token"] = SecureRandom.hex(8)
        scan["active_job_token"] = nil
        store(scan)
        scan
      end

      begin
        Jobs.enqueue(
          Jobs::DisifyExistingUserScan,
          scan_id: current["scan_id"],
          job_token: current["queued_job_token"],
        )
      rescue StandardError
        pause_error_if_active!(
          current["scan_id"],
          "enqueue_failed",
          queued_token: current["queued_job_token"],
        )
        raise
      end
      public_state(current)
    end

    def cancel!(actor:)
      raise Discourse::InvalidAccess unless actor&.admin?

      with_state_lock do
        current = normalize_stale_without_lock!(raw_state)
        next public_state(current) unless BLOCKING_STATUSES.include?(current["status"])

        now = Time.zone.now.iso8601
        current["status"] = "cancelled"
        current["cancelled_at"] = now
        current["cancelled_by_id"] = actor.id
        current["last_activity_at"] = now
        current["next_run_at"] = nil
        current["last_error"] = nil
        current["queued_job_token"] = nil
        current["active_job_token"] = nil
        store(current)
        public_state(current)
      end
    end

    def process_batch!(scan_id, job_token = nil)
      execution_token = nil
      claimed = claim_job!(scan_id, job_token)
      return if claimed.nil?

      current, execution_token = claimed

      unless SiteSetting.disify_email_protection_enabled
        pause_error_if_active!(scan_id, "plugin_disabled", execution_token)
        return
      end

      if CircuitBreaker.open?
        wait_for_provider!(current, scan_id, "circuit_open", execution_token)
        return
      end

      batch_size = [[SiteSetting.disify_email_protection_max_scan_batch_size.to_i, 10].max, 500].min
      users =
        User.real
          .where(staged: false)
          .where("id > ?", current["cursor"].to_i)
          .order(:id)
          .limit(batch_size)
          .preload(:primary_email)
          .to_a

      if users.empty?
        complete_if_active!(current, scan_id, execution_token)
        return
      end

      processed_since_checkpoint = 0
      users.each do |user|
        return unless still_active?(scan_id, execution_token)

        unless SiteSetting.disify_email_protection_enabled
          pause_error_if_active!(scan_id, "plugin_disabled", execution_token)
          return
        end

        email = user.email.to_s
        if email.blank? || ReviewQueue.anonymized_user?(user)
          current["processed"] = current["processed"].to_i + 1
          current["cursor"] = user.id
          current["last_activity_at"] = Time.zone.now.iso8601
          processed_since_checkpoint += 1
          if processed_since_checkpoint >= CHECKPOINT_EVERY
            return unless checkpoint_progress_if_active!(current, scan_id, execution_token)
            processed_since_checkpoint = 0
          end
          next
        end

        scan_mode = current["mode"]
        domain = Normalizer.domain(email)
        trusted_provider_full_check =
          SiteSetting.disify_email_protection_trusted_provider_email_check && Normalizer.trusted_alias_domain?(domain)
        domain_only =
          scan_mode == "domain_only" ||
            (scan_mode == "trusted_providers" && !trusted_provider_full_check)

        result = Decision.evaluate(
          email: email,
          user: user,
          flow: "existing_user_scan",
          force_remote: false,
          dry_run: true,
          domain_only: domain_only,
          mode_override: "monitor",
        )

        return unless still_active?(scan_id, execution_token)

        unless SiteSetting.disify_email_protection_enabled
          pause_error_if_active!(scan_id, "plugin_disabled", execution_token)
          return
        end

        if result.status == "unavailable"
          wait_for_provider!(current, scan_id, result.reason.to_s.presence || "provider_unavailable", execution_token)
          return
        end

        if risky_result?(result)
          review_item = ReviewQueue.create_or_refresh!(
            email: email,
            user: user,
            flow: "existing_user_scan",
            reason: result.reason,
            confidence: result.confidence,
            signals: result.signals,
            metadata: { "source" => result.source, "scan_id" => scan_id },
          )
          if SiteSetting.disify_email_protection_review_queue_enabled && review_item.nil?
            pause_error_if_active!(scan_id, "review_queue_write_failed", execution_token)
            return
          end

          current["flagged"] = current["flagged"].to_i + 1
          UserNoteWriter.record!(
            user: user,
            reason: result.reason,
            domain: domain,
            confidence: result.confidence,
            context: "manual existing-user scan flagged this account",
          )
        end

        current["processed"] = current["processed"].to_i + 1
        current["cursor"] = user.id
        current["last_activity_at"] = Time.zone.now.iso8601
        processed_since_checkpoint += 1
        if processed_since_checkpoint >= CHECKPOINT_EVERY
          return unless checkpoint_progress_if_active!(current, scan_id, execution_token)
          processed_since_checkpoint = 0
        end

        if result.source == "api" && provider_rate_limit_nearly_exhausted?
          wait_for_provider!(current, scan_id, "rate_limit_window", execution_token)
          return
        end
      end

      next_job_token = schedule_next_if_active!(current, scan_id, execution_token)
      if next_job_token.present?
        begin
          Jobs.enqueue_in(
            NORMAL_BATCH_DELAY,
            :disify_existing_user_scan,
            { scan_id: scan_id, job_token: next_job_token },
          )
        rescue StandardError
          pause_error_if_active!(scan_id, "enqueue_failed", queued_token: next_job_token)
          raise
        end
      end
    rescue StandardError => e
      pause_error_if_active!(scan_id, e.class.to_s, execution_token)
      Rails.logger.warn("[disify_email_protection] existing scan paused class=#{e.class}")
    end

    def wait_for_provider!(current, scan_id, reason, execution_token = nil)
      open_until = CircuitBreaker.open_until
      delay = if open_until.present? && open_until > Time.zone.now
        [(open_until - Time.zone.now).ceil + 5, NORMAL_BATCH_DELAY.to_i].max.seconds
      else
        NORMAL_BATCH_DELAY
      end

      next_job_token = with_state_lock do
        latest = raw_state
        next nil unless owned_active_state?(latest, scan_id, execution_token)

        now = Time.zone.now
        merge_progress!(latest, current)
        token = SecureRandom.hex(8)
        latest["status"] = "waiting"
        latest["last_error"] = reason
        latest["last_activity_at"] = now.iso8601
        latest["next_run_at"] = (now + delay).iso8601
        latest["active_job_token"] = nil
        latest["queued_job_token"] = token
        store(latest)
        token
      end

      return if next_job_token.blank?

      begin
        Jobs.enqueue_in(
          delay,
          :disify_existing_user_scan,
          { scan_id: scan_id, job_token: next_job_token },
        )
      rescue StandardError
        pause_error_if_active!(scan_id, "enqueue_failed", queued_token: next_job_token)
        raise
      end
    end

    def provider_rate_limit_nearly_exhausted?
      health = Health.stored_health
      limit = Integer(health["rate_limit_limit"], exception: false)
      remaining = Integer(health["rate_limit_remaining"], exception: false)
      limit.present? && limit.positive? && remaining.present? && remaining <= PROVIDER_RATE_LIMIT_RESERVE
    rescue StandardError
      false
    end

    def risky_result?(result)
      return false if %w[allow bypass fail_open].include?(result.decision.to_s)

      %w[disposable no_mx role].include?(result.reason.to_s) || result.decision == "block"
    end

    def state
      public_state(with_state_lock { normalize_stale_without_lock!(raw_state) })
    end

    def raw_state
      value = PluginStore.get(STORE_NAMESPACE, STATE_KEY)
      value.is_a?(Hash) ? value.deep_stringify_keys : { "status" => "idle" }
    end

    def claim_job!(scan_id, job_token = nil)
      supplied_token = job_token.to_s.presence
      return nil if supplied_token.present? && !JOB_TOKEN_PATTERN.match?(supplied_token)

      with_state_lock do
        scan = normalize_stale_without_lock!(raw_state)
        next nil unless scan["scan_id"] == scan_id && ACTIVE_STATUSES.include?(scan["status"])

        queued_token = scan["queued_job_token"].to_s.presence
        active_token = scan["active_job_token"].to_s.presence

        if queued_token.present?
          next nil unless supplied_token == queued_token
        elsif supplied_token.present? || active_token.present?
          # A tokened job with no matching queued token is stale/duplicate. A legacy
          # tokenless job may claim only when no worker is already active.
          next nil
        end

        execution_token = queued_token || SecureRandom.hex(8)
        was_waiting = scan["status"] == "waiting"
        scan["status"] = "running"
        scan["last_activity_at"] = Time.zone.now.iso8601
        scan["next_run_at"] = nil
        scan["last_error"] = nil if was_waiting
        scan["queued_job_token"] = nil
        scan["active_job_token"] = execution_token
        store(scan)
        [scan, execution_token]
      end
    end

    def still_active?(scan_id, execution_token = nil)
      owned_active_state?(raw_state, scan_id, execution_token)
    end

    def checkpoint_progress_if_active!(current, scan_id, execution_token = nil)
      with_state_lock do
        latest = raw_state
        next false unless owned_active_state?(latest, scan_id, execution_token)

        now = Time.zone.now.iso8601
        merge_progress!(latest, current)
        latest["last_activity_at"] = now
        store(latest)
        current["last_activity_at"] = now
        true
      end
    end

    def complete_if_active!(current, scan_id, execution_token = nil)
      with_state_lock do
        latest = raw_state
        next false unless owned_active_state?(latest, scan_id, execution_token)

        now = Time.zone.now.iso8601
        merge_progress!(latest, current)
        latest["status"] = "completed"
        latest["completed_at"] = now
        latest["last_activity_at"] = now
        latest["next_run_at"] = nil
        latest["active_job_token"] = nil
        latest["queued_job_token"] = nil
        store(latest)
        true
      end
    end

    def schedule_next_if_active!(current, scan_id, execution_token = nil)
      with_state_lock do
        latest = raw_state
        next nil unless owned_active_state?(latest, scan_id, execution_token)

        now = Time.zone.now
        merge_progress!(latest, current)
        token = SecureRandom.hex(8)
        latest["status"] = "running"
        latest["last_activity_at"] = now.iso8601
        latest["next_run_at"] = (now + NORMAL_BATCH_DELAY).iso8601
        latest["active_job_token"] = nil
        latest["queued_job_token"] = token
        store(latest)
        token
      end
    end

    def pause_error_if_active!(scan_id, error_code, execution_token = nil, queued_token: nil)
      with_state_lock do
        latest = raw_state
        next latest unless latest["scan_id"] == scan_id && ACTIVE_STATUSES.include?(latest["status"])

        if execution_token.present?
          next latest unless latest["active_job_token"].to_s == execution_token.to_s
        elsif queued_token.present?
          next latest unless latest["queued_job_token"].to_s == queued_token.to_s
        elsif latest["active_job_token"].present? || latest["queued_job_token"].present?
          next latest
        end

        now = Time.zone.now.iso8601
        latest["status"] = "paused"
        latest["paused_at"] = now
        latest["last_activity_at"] = now
        latest["next_run_at"] = nil
        latest["last_error"] = error_code
        latest["active_job_token"] = nil
        latest["queued_job_token"] = nil
        store(latest)
        latest
      end
    end

    def owned_active_state?(latest, scan_id, execution_token)
      return false unless latest["scan_id"] == scan_id && ACTIVE_STATUSES.include?(latest["status"])

      active_token = latest["active_job_token"].to_s.presence
      return active_token.blank? if execution_token.blank?

      active_token == execution_token.to_s
    end

    def merge_progress!(latest, current)
      latest["cursor"] = [latest["cursor"].to_i, current["cursor"].to_i].max
      latest["processed"] = [latest["processed"].to_i, current["processed"].to_i].max
      latest["flagged"] = [latest["flagged"].to_i, current["flagged"].to_i].max
      latest
    end

    def public_state(value)
      value.to_h.except("queued_job_token", "active_job_token")
    end

    def normalize_stale_without_lock!(current)
      return current unless ACTIVE_STATUSES.include?(current["status"])
      return current unless stale?(current)

      now = Time.zone.now.iso8601
      current["status"] = "paused"
      current["paused_at"] = now
      current["last_activity_at"] = now
      current["next_run_at"] = nil
      current["last_error"] = "stale_scan"
      current["queued_job_token"] = nil
      current["active_job_token"] = nil
      store(current)
      current
    end

    def stale?(current)
      now = Time.zone.now
      next_run_at = parse_time(current["next_run_at"])

      if next_run_at.present?
        return false if next_run_at >= now
        return next_run_at < now - STALE_AFTER
      end

      last_activity_at = parse_time(current["last_activity_at"] || current["started_at"])
      last_activity_at.present? && last_activity_at < now - STALE_AFTER
    end

    def normalize_request_id(value)
      raw = value.to_s.strip
      return nil if raw.blank?
      raise Discourse::InvalidParameters.new(:request_id) unless REQUEST_ID_PATTERN.match?(raw)

      raw
    end

    def parse_time(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def with_state_lock(&block)
      DistributedMutex.synchronize(STATE_MUTEX_KEY, validity: 10, &block)
    end

    def store(value)
      PluginStore.set(STORE_NAMESPACE, STATE_KEY, value)
    end
  end
end

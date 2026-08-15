# frozen_string_literal: true

module ::DisifyEmailProtection
  module ExistingUserScan
    module_function

    STATE_KEY = "existing_user_scan"
    STATE_MUTEX_KEY = "disify-email-protection-existing-user-scan-state"
    NORMAL_BATCH_DELAY = 65.seconds
    STALE_AFTER = 10.minutes
    ACTIVE_STATUSES = %w[running waiting].freeze
    BLOCKING_STATUSES = %w[running waiting paused].freeze

    def start!(actor:, scan_mode: nil)
      raise Discourse::InvalidAccess unless actor&.admin?
      raise Discourse::InvalidParameters.new(:scan) unless SiteSetting.disify_email_protection_manual_scan_enabled

      mode = scan_mode.to_s.presence || SiteSetting.disify_email_protection_manual_scan_full_email_mode.to_s
      raise Discourse::InvalidParameters.new(:scan_mode) unless %w[domain_only trusted_providers all].include?(mode)

      payload = with_state_lock do
        current = normalize_stale_without_lock!(raw_state)
        if BLOCKING_STATUSES.include?(current["status"])
          raise Discourse::InvalidParameters.new(:scan_already_running)
        end

        now = Time.zone.now
        scan_id = SecureRandom.hex(8)
        new_state = {
          "scan_id" => scan_id,
          "status" => "running",
          "mode" => mode,
          "started_at" => now.iso8601,
          "started_by_id" => actor.id,
          "last_activity_at" => now.iso8601,
          "next_run_at" => nil,
          "cursor" => 0,
          "processed" => 0,
          "flagged" => 0,
          "total" => User.real.where(staged: false).count,
          "last_error" => nil,
        }
        store(new_state)
        new_state
      end

      Jobs.enqueue(:disify_existing_user_scan, scan_id: payload["scan_id"])
      payload
    end

    def resume!(actor:)
      raise Discourse::InvalidAccess unless actor&.admin?

      current = with_state_lock do
        scan = normalize_stale_without_lock!(raw_state)
        raise Discourse::InvalidParameters.new(:scan) unless scan["status"] == "paused"

        scan["status"] = "running"
        scan["last_error"] = nil
        scan["paused_at"] = nil
        scan["last_activity_at"] = Time.zone.now.iso8601
        scan["next_run_at"] = nil
        store(scan)
        scan
      end

      Jobs.enqueue(:disify_existing_user_scan, scan_id: current["scan_id"])
      current
    end

    def cancel!(actor:)
      raise Discourse::InvalidAccess unless actor&.admin?

      with_state_lock do
        current = normalize_stale_without_lock!(raw_state)
        next current unless BLOCKING_STATUSES.include?(current["status"])

        now = Time.zone.now.iso8601
        current["status"] = "cancelled"
        current["cancelled_at"] = now
        current["cancelled_by_id"] = actor.id
        current["last_activity_at"] = now
        current["next_run_at"] = nil
        current["last_error"] = nil
        store(current)
        current
      end
    end

    def process_batch!(scan_id)
      current = with_state_lock do
        scan = normalize_stale_without_lock!(raw_state)
        next nil unless scan["scan_id"] == scan_id && ACTIVE_STATUSES.include?(scan["status"])

        scan["status"] = "running"
        scan["last_activity_at"] = Time.zone.now.iso8601
        scan["next_run_at"] = nil
        scan["last_error"] = nil if scan["last_error"] == "circuit_open"
        store(scan)
        scan
      end
      return if current.nil?

      if CircuitBreaker.open?
        wait_for_provider!(current, scan_id, "circuit_open")
        return
      end

      batch_size = [[SiteSetting.disify_email_protection_max_scan_batch_size.to_i, 10].max, 500].min
      users = User.real.where(staged: false).where("id > ?", current["cursor"].to_i).order(:id).limit(batch_size).to_a

      if users.empty?
        complete_if_active!(current, scan_id)
        return
      end

      users.each do |user|
        return unless still_active?(scan_id)

        email = user.email.to_s
        if email.blank?
          current["processed"] = current["processed"].to_i + 1
          current["cursor"] = user.id
          current["last_activity_at"] = Time.zone.now.iso8601
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

        return unless still_active?(scan_id)

        if result.status == "unavailable"
          wait_for_provider!(current, scan_id, result.reason.to_s.presence || "provider_unavailable")
          return
        end

        if risky_result?(result)
          ReviewQueue.create_or_refresh!(
            email: email,
            user: user,
            flow: "existing_user_scan",
            reason: result.reason,
            confidence: result.confidence,
            signals: result.signals,
            metadata: { "source" => result.source, "scan_id" => scan_id },
          )
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
      end

      scheduled = schedule_next_if_active!(current, scan_id)
      Jobs.enqueue_in(NORMAL_BATCH_DELAY, :disify_existing_user_scan, { scan_id: scan_id }) if scheduled
    rescue StandardError => e
      pause_error_if_active!(scan_id, e.class.to_s)
      Rails.logger.warn("[disify_email_protection] existing scan paused class=#{e.class}")
    end

    def wait_for_provider!(current, scan_id, reason)
      open_until = CircuitBreaker.open_until
      delay = if open_until.present? && open_until > Time.zone.now
        [(open_until - Time.zone.now).ceil + 5, NORMAL_BATCH_DELAY.to_i].max.seconds
      else
        NORMAL_BATCH_DELAY
      end

      scheduled = with_state_lock do
        latest = raw_state
        next false unless latest["scan_id"] == scan_id && ACTIVE_STATUSES.include?(latest["status"])

        now = Time.zone.now
        current["status"] = "waiting"
        current["last_error"] = reason
        current["last_activity_at"] = now.iso8601
        current["next_run_at"] = (now + delay).iso8601
        store(current)
        true
      end

      Jobs.enqueue_in(delay, :disify_existing_user_scan, { scan_id: scan_id }) if scheduled
    end

    def risky_result?(result)
      %w[disposable no_mx role].include?(result.reason.to_s) || result.decision == "block"
    end

    def state
      with_state_lock { normalize_stale_without_lock!(raw_state) }
    end

    def raw_state
      value = PluginStore.get(STORE_NAMESPACE, STATE_KEY)
      value.is_a?(Hash) ? value.deep_stringify_keys : { "status" => "idle" }
    end

    def still_active?(scan_id)
      latest = raw_state
      latest["scan_id"] == scan_id && ACTIVE_STATUSES.include?(latest["status"])
    end

    def complete_if_active!(current, scan_id)
      with_state_lock do
        latest = raw_state
        next false unless latest["scan_id"] == scan_id && ACTIVE_STATUSES.include?(latest["status"])

        now = Time.zone.now.iso8601
        current["status"] = "completed"
        current["completed_at"] = now
        current["last_activity_at"] = now
        current["next_run_at"] = nil
        store(current)
        true
      end
    end

    def schedule_next_if_active!(current, scan_id)
      with_state_lock do
        latest = raw_state
        next false unless latest["scan_id"] == scan_id && ACTIVE_STATUSES.include?(latest["status"])

        now = Time.zone.now
        current["status"] = "running"
        current["last_activity_at"] = now.iso8601
        current["next_run_at"] = (now + NORMAL_BATCH_DELAY).iso8601
        store(current)
        true
      end
    end

    def pause_error_if_active!(scan_id, error_code)
      with_state_lock do
        latest = raw_state
        next latest unless latest["scan_id"] == scan_id && ACTIVE_STATUSES.include?(latest["status"])

        now = Time.zone.now.iso8601
        latest["status"] = "paused"
        latest["paused_at"] = now
        latest["last_activity_at"] = now
        latest["next_run_at"] = nil
        latest["last_error"] = error_code
        store(latest)
        latest
      end
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

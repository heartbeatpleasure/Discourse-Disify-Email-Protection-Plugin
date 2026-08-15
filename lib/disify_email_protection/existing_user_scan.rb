# frozen_string_literal: true

module ::DisifyEmailProtection
  module ExistingUserScan
    module_function

    STATE_KEY = "existing_user_scan"
    NORMAL_BATCH_DELAY = 65.seconds

    def start!(actor:, scan_mode: nil)
      raise Discourse::InvalidAccess unless actor&.admin?
      raise Discourse::InvalidParameters.new(:scan) unless SiteSetting.disify_email_protection_manual_scan_enabled

      current = state
      if %w[running waiting paused].include?(current["status"])
        raise Discourse::InvalidParameters.new(:scan_already_running)
      end

      mode = scan_mode.to_s.presence || SiteSetting.disify_email_protection_manual_scan_full_email_mode.to_s
      raise Discourse::InvalidParameters.new(:scan_mode) unless %w[domain_only trusted_providers all].include?(mode)

      scan_id = SecureRandom.hex(8)
      payload = {
        "scan_id" => scan_id,
        "status" => "running",
        "mode" => mode,
        "started_at" => Time.zone.now.iso8601,
        "started_by_id" => actor.id,
        "cursor" => 0,
        "processed" => 0,
        "flagged" => 0,
        "total" => User.real.where(staged: false).count,
        "last_error" => nil,
      }
      store(payload)
      Jobs.enqueue(:disify_existing_user_scan, scan_id: scan_id)
      payload
    end

    def resume!(actor:)
      raise Discourse::InvalidAccess unless actor&.admin?
      current = state
      raise Discourse::InvalidParameters.new(:scan) unless current["status"] == "paused"

      current["status"] = "running"
      current["last_error"] = nil
      store(current)
      Jobs.enqueue(:disify_existing_user_scan, scan_id: current["scan_id"])
      current
    end

    def process_batch!(scan_id)
      current = state
      return if current["scan_id"] != scan_id || !%w[running waiting].include?(current["status"])

      if CircuitBreaker.open?
        wait_for_provider!(current, scan_id, "circuit_open")
        return
      end

      current["status"] = "running"
      current["last_error"] = nil if current["last_error"] == "circuit_open"

      batch_size = [[SiteSetting.disify_email_protection_max_scan_batch_size.to_i, 10].max, 500].min
      users = User.real.where(staged: false).where("id > ?", current["cursor"].to_i).order(:id).limit(batch_size).to_a

      if users.empty?
        current["status"] = "completed"
        current["completed_at"] = Time.zone.now.iso8601
        store(current)
        return
      end

      users.each do |user|
        email = user.email.to_s
        if email.blank?
          current["processed"] = current["processed"].to_i + 1
          current["cursor"] = user.id
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
      end

      store(current)
      Jobs.enqueue_in(NORMAL_BATCH_DELAY, :disify_existing_user_scan, { scan_id: scan_id })
    rescue StandardError => e
      current ||= state
      current["status"] = "paused"
      current["last_error"] = e.class.to_s
      store(current)
      Rails.logger.warn("[disify_email_protection] existing scan paused class=#{e.class}")
    end

    def wait_for_provider!(current, scan_id, reason)
      current["status"] = "waiting"
      current["last_error"] = reason
      store(current)

      open_until = CircuitBreaker.open_until
      delay = if open_until.present? && open_until > Time.zone.now
        [(open_until - Time.zone.now).ceil + 5, NORMAL_BATCH_DELAY.to_i].max.seconds
      else
        NORMAL_BATCH_DELAY
      end
      Jobs.enqueue_in(delay, :disify_existing_user_scan, { scan_id: scan_id })
    end

    def risky_result?(result)
      %w[disposable no_mx role].include?(result.reason.to_s) || result.decision == "block"
    end

    def state
      value = PluginStore.get(STORE_NAMESPACE, STATE_KEY)
      value.is_a?(Hash) ? value.deep_stringify_keys : { "status" => "idle" }
    end

    def store(value)
      PluginStore.set(STORE_NAMESPACE, STATE_KEY, value)
    end
  end
end

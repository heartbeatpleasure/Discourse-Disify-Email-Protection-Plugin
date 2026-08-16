# frozen_string_literal: true

module ::DisifyEmailProtection
  module Decision
    DecisionResult = Struct.new(
      :decision,
      :reason,
      :confidence,
      :signals,
      :source,
      :status,
      :latency_ms,
      :user_message_key,
      :payload,
      keyword_init: true,
    )

    module_function

    def evaluate(
      email:,
      user: nil,
      flow: "signup",
      force_remote: false,
      dry_run: false,
      domain_only: false,
      mode_override: nil,
      ignore_exceptions: false
    )
      normalized = Normalizer.email(email)
      domain = Normalizer.domain(normalized)
      mode = mode_override.presence || SiteSetting.disify_email_protection_mode.to_s

      return allow_result("invalid_format") if normalized.blank? || domain.blank?
      return allow_result("disabled") unless SiteSetting.disify_email_protection_enabled || dry_run

      exception = ignore_exceptions ? nil : PolicyExceptions.decision_for(normalized)
      if exception == "bypass"
        return finalize(
          normalized,
          user,
          flow,
          mode,
          "bypass",
          "exception",
          nil,
          [],
          "success",
          nil,
          "exception",
          {},
          dry_run,
        )
      elsif exception == "block"
        return finalize(
          normalized,
          user,
          flow,
          mode,
          apply_mode("block", mode),
          "policy_block",
          nil,
          [],
          "success",
          nil,
          "exception",
          {},
          dry_run,
        )
      end

      # Prefer a still-valid local cache entry before consulting the circuit breaker.
      # This preserves known risky-domain enforcement during a provider outage or
      # rate-limit window instead of turning every cached result into fail-open.
      cached = nil
      unless force_remote
        if domain_only
          cached = Cache.fetch_domain(domain)
        else
          cached = Cache.fetch_email(normalized)
          cached ||= Cache.fetch_risky_domain(domain)
        end
      end

      telemetry = {}
      if cached.present?
        payload = cached["result"].to_h.deep_stringify_keys
        status = "success"
        latency = nil
        source = "cache"
        telemetry[:cache_hits] = 1
      else
        unless force_remote || CircuitBreaker.allow_request?
          return unavailable_decision(
            normalized,
            user,
            flow,
            mode,
            "circuit_open",
            dry_run,
            nil,
            source: "circuit",
          )
        end

        client_result = domain_only ? Client.new.check_domain(domain) : Client.new.check_email(normalized)
        Health.record_result!(client_result, source: flow)
        telemetry = remote_telemetry(client_result)

        unless client_result.success
          CircuitBreaker.record_failure!(client_result)
          return unavailable_decision(
            normalized,
            user,
            flow,
            mode,
            client_result.error_code.to_s,
            dry_run,
            client_result,
            telemetry: telemetry,
          )
        end

        CircuitBreaker.record_success!
        payload = client_result.payload.to_h.deep_stringify_keys
        status = "success"
        latency = client_result.latency_ms
        source = "api"
        if domain_only || !Normalizer.trusted_alias_domain?(domain)
          Cache.write_domain(domain, payload)
        end
        Cache.write_email(normalized, payload) unless domain_only
      end

      requested_action, reason, message_key = policy_for(payload)
      decision = apply_mode(requested_action, mode)

      finalize(
        normalized,
        user,
        flow,
        mode,
        decision,
        reason,
        payload["confidence"],
        Array(payload["signals"]),
        status,
        latency,
        source,
        payload,
        dry_run,
        message_key,
        telemetry: telemetry,
      )
    end

    def policy_for(payload)
      return ["block", "invalid_format", "invalid_format"] if payload["format"] == false

      if SiteSetting.disify_email_protection_block_no_mx && payload["dns"] == false
        return ["block", "no_mx", "no_mx"]
      end

      threshold = SiteSetting.disify_email_protection_disposable_confidence_threshold.to_i
      if SiteSetting.disify_email_protection_block_disposable &&
           payload["disposable"] == true &&
           payload["confidence"].to_i >= threshold
        return ["block", "disposable", "disposable_email"]
      end

      if payload["disposable"] == true
        return ["monitor", "disposable_low_confidence", nil]
      end

      if payload["role"] == true
        action = SiteSetting.disify_email_protection_role_email_action.to_s
        return [action == "ignore" ? "allow" : action, "role", action == "block" ? "role_email" : nil]
      end

      ["allow", "clean", nil]
    end

    def apply_mode(requested_action, mode)
      return "allow" if requested_action == "allow"
      return "monitor" if requested_action == "monitor"

      case mode
      when "monitor"
        "monitor"
      when "review"
        "review"
      else
        requested_action == "review" ? "review" : "block"
      end
    end

    def unavailable_decision(
      email,
      user,
      flow,
      mode,
      reason,
      dry_run,
      client_result = nil,
      source: "api",
      telemetry: {}
    )
      if SiteSetting.disify_email_protection_fail_open || dry_run
        finalize(
          email,
          user,
          flow,
          mode,
          "fail_open",
          reason,
          nil,
          [],
          "unavailable",
          client_result&.latency_ms,
          source,
          {},
          dry_run,
          nil,
          telemetry: telemetry,
        )
      else
        finalize(
          email,
          user,
          flow,
          mode,
          "block",
          reason,
          nil,
          [],
          "unavailable",
          client_result&.latency_ms,
          source,
          {},
          dry_run,
          "service_unavailable",
          telemetry: telemetry,
        )
      end
    end

    def finalize(
      email,
      user,
      flow,
      mode,
      decision,
      reason,
      confidence,
      signals,
      status,
      latency_ms,
      source,
      payload,
      dry_run,
      message_key = nil,
      telemetry: {}
    )
      unless dry_run
        EventRecorder.record!(
          email: email,
          user: user,
          flow: flow,
          mode: mode,
          decision: decision,
          reason: reason,
          confidence: confidence,
          signals: signals,
          status: status,
          latency_ms: latency_ms,
          source: source,
        )

        counters = {
          checked: 1,
          allowed: 0,
          monitored: 0,
          reviewed: 0,
          blocked_disposable: 0,
          blocked_no_mx: 0,
          blocked_other: 0,
          fail_open: 0,
          bypassed: 0,
          api_errors: 0,
        }.merge(telemetry.symbolize_keys)

        case decision
        when "allow" then counters[:allowed] = 1
        when "monitor" then counters[:monitored] = 1
        when "review" then counters[:reviewed] = 1
        when "fail_open" then counters[:fail_open] = 1
        when "bypass" then counters[:bypassed] = 1
        when "block"
          if reason == "disposable"
            counters[:blocked_disposable] = 1
          elsif reason == "no_mx"
            counters[:blocked_no_mx] = 1
          else
            counters[:blocked_other] = 1
          end
        end

        counters[:api_errors] = 1 if status == "unavailable" && counters[:api_calls].to_i.positive?
        Statistics.increment!(counters)

        if decision == "review" && user&.persisted?
          ReviewQueue.create_or_refresh!(
            email: email,
            user: user,
            flow: flow,
            reason: reason,
            confidence: confidence,
            signals: signals,
            metadata: { "source" => source },
          )
        end

        if user&.persisted? && %w[block review].include?(decision)
          UserNoteWriter.record!(
            user: user,
            reason: reason,
            domain: Normalizer.domain(email),
            confidence: confidence,
            context: decision == "review" ? "review item created" : "email change blocked",
          )
        end
      end

      DecisionResult.new(
        decision: decision,
        reason: reason,
        confidence: confidence,
        signals: signals,
        source: source,
        status: status,
        latency_ms: latency_ms,
        user_message_key: message_key || default_message_key(reason),
        payload: payload,
      )
    end

    def remote_telemetry(client_result)
      {
        api_calls: 1,
        latency_total_ms: client_result.latency_ms.to_i,
        latency_samples: client_result.latency_ms.present? ? 1 : 0,
      }
    end

    def default_message_key(reason)
      case reason.to_s
      when "disposable" then "disposable_email"
      when "no_mx" then "no_mx"
      when "invalid_format" then "invalid_format"
      when "role" then "role_email"
      when "policy_block" then "policy_block"
      else "policy_block"
      end
    end

    def allow_result(reason)
      DecisionResult.new(
        decision: "allow",
        reason: reason,
        confidence: nil,
        signals: [],
        source: "local",
        status: "skipped",
        latency_ms: nil,
        user_message_key: nil,
        payload: {},
      )
    end
  end
end

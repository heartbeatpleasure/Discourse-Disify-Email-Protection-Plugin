# frozen_string_literal: true

module ::DisifyEmailProtection
  module Health
    module_function

    HEALTH_KEY = "health_state"
    HEALTH_MUTEX_KEY = "disify-email-protection-health-state"

    def payload
      health = stored_health
      circuit = CircuitBreaker.state
      today = Statistics.today_payload

      {
        generated_at: Time.zone.now.iso8601,
        overall: overall_status(health, circuit),
        configuration: {
          enabled: SiteSetting.disify_email_protection_enabled,
          mode: SiteSetting.disify_email_protection_mode,
          fail_open: SiteSetting.disify_email_protection_fail_open,
          api_key_configured: SiteSetting.disify_email_protection_api_key.present?,
          auth_mode: SiteSetting.disify_email_protection_api_key.present? ? SiteSetting.disify_email_protection_api_auth_mode : "anonymous",
          provider_host: "disify.com",
          timeout_ms: SiteSetting.disify_email_protection_timeout_ms.to_i,
        },
        provider: health,
        circuit_breaker: circuit,
        today: today,
        privacy: {
          raw_email_stored_in_plugin_tables: false,
          api_key_exposed_to_client: false,
          full_api_response_stored: false,
          email_hmac_used_for_correlation: true,
        },
      }
    end

    def test!
      result = Client.new.check_domain("gmail.com")
      record_result!(result, source: "health_test")
      if result.success
        CircuitBreaker.record_success!
      else
        CircuitBreaker.record_failure!(result)
      end
      payload.merge(test_result: result_summary(result))
    end

    def scheduled_test!
      return { skipped: true, reason: "plugin_disabled" } unless SiteSetting.disify_email_protection_enabled

      result = Client.new.check_domain("gmail.com")
      record_result!(result, source: "scheduled_health")
      result.success ? CircuitBreaker.record_success! : CircuitBreaker.record_failure!(result)
      result_summary(result)
    end

    def record_result!(result, source:)
      DistributedMutex.synchronize(HEALTH_MUTEX_KEY, validity: 10) do
        current = stored_health
        now = Time.zone.now.iso8601
        current["last_check_at"] = now
        current["last_source"] = source.to_s.first(64)
        current["last_latency_ms"] = result.latency_ms
        current["rate_limit_limit"] = result.rate_limit_limit
        current["rate_limit_remaining"] = result.rate_limit_remaining
        current["reset_at"] = result.reset_at&.iso8601

        if result.success
          current["last_success_at"] = now
          current["last_error_at"] = nil
          current["last_error_code"] = nil
          current["last_error_message"] = nil
        else
          current["last_error_at"] = now
          current["last_error_code"] = result.error_code.to_s.first(64)
          current["last_error_message"] = nil
        end

        PluginStore.set(STORE_NAMESPACE, HEALTH_KEY, current)
        current
      end
    rescue StandardError => e
      Rails.logger.warn("[disify_email_protection] health persistence failed class=#{e.class}")
      {}
    end

    def stored_health
      value = PluginStore.get(STORE_NAMESPACE, HEALTH_KEY)
      value.is_a?(Hash) ? value.deep_stringify_keys : {}
    end

    def overall_status(health, circuit)
      return "disabled" unless SiteSetting.disify_email_protection_enabled
      return "misconfigured" if %w[invalid_key access_denied].include?(health["last_error_code"])
      return "quota_exhausted" if health["last_error_code"] == "quota_exceeded"
      return "circuit_open" if circuit[:state] == "open"
      return "degraded" if health["last_error_at"].present?

      "healthy"
    end

    def result_summary(result)
      {
        success: result.success,
        status: result.status,
        error_code: result.error_code&.to_s,
        latency_ms: result.latency_ms,
        rate_limit_limit: result.rate_limit_limit,
        rate_limit_remaining: result.rate_limit_remaining,
        retry_after: result.retry_after,
        reset_at: result.reset_at&.iso8601,
      }
    end
  end
end

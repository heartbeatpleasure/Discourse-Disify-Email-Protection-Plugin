# frozen_string_literal: true

module ::DisifyEmailProtection
  module CircuitBreaker
    module_function

    PREFIX = "disify_email_protection:circuit"
    FAILURE_KEY = "#{PREFIX}:failures"
    OPEN_UNTIL_KEY = "#{PREFIX}:open_until"
    REASON_KEY = "#{PREFIX}:reason"
    FAILURE_WINDOW = 5.minutes
    DEFAULT_OPEN = 5.minutes

    def state
      until_time = open_until
      {
        state: until_time.present? && until_time > Time.zone.now ? "open" : "closed",
        open_until: until_time&.iso8601,
        reason: Discourse.redis.get(REASON_KEY),
        consecutive_failures: Discourse.redis.get(FAILURE_KEY).to_i,
      }
    end

    def open?
      open_until_time = open_until
      if open_until_time.present? && open_until_time <= Time.zone.now
        close!
        return false
      end

      open_until_time.present?
    end

    def allow_request?
      !open?
    end

    def record_success!
      close!
    end

    def record_failure!(result)
      code = result.error_code.to_s

      case code
      when "invalid_key", "access_denied"
        open_for!(15.minutes, code)
      when "rate_limited"
        seconds = [[result.retry_after.to_i, 30].max, 15.minutes.to_i].min
        open_for!(seconds.seconds, code)
      when "quota_exceeded"
        duration = if result.reset_at.present? && result.reset_at > Time.zone.now
          [result.reset_at - Time.zone.now, 24.hours].min
        else
          1.hour
        end
        open_for!(duration, code)
      else
        failures = Discourse.redis.incr(FAILURE_KEY)
        Discourse.redis.expire(FAILURE_KEY, FAILURE_WINDOW.to_i)
        open_for!(DEFAULT_OPEN, code) if failures >= 3
      end
    rescue StandardError => e
      Rails.logger.warn("[disify_email_protection] circuit update failed class=#{e.class}")
    end

    def reset!
      close!
    end

    def open_until
      raw = Discourse.redis.get(OPEN_UNTIL_KEY)
      return nil if raw.blank?

      Time.at(raw.to_i).in_time_zone
    end

    def open_for!(duration, reason)
      seconds = [duration.to_i, 1].max
      until_epoch = Time.zone.now.to_i + seconds
      Discourse.redis.setex(OPEN_UNTIL_KEY, seconds, until_epoch)
      Discourse.redis.setex(REASON_KEY, seconds, reason.to_s)
    end

    def close!
      Discourse.redis.del(FAILURE_KEY, OPEN_UNTIL_KEY, REASON_KEY)
    end
  end
end

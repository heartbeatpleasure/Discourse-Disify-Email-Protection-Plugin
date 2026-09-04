# frozen_string_literal: true

module ::DisifyEmailProtection
  module CircuitBreaker
    module_function

    PREFIX = "disify_email_protection:circuit"
    FAILURE_KEY = "#{PREFIX}:failures"
    OPEN_UNTIL_KEY = "#{PREFIX}:open_until"
    REASON_KEY = "#{PREFIX}:reason"
    STATE_MUTEX_KEY = "disify-email-protection-circuit-state"
    FAILURE_WINDOW = 5.minutes
    DEFAULT_OPEN = 5.minutes
    PROTECTED_BACKOFF_REASONS = %w[rate_limited quota_exceeded].freeze

    def state
      until_time = open_until
      {
        state: until_time.present? && until_time > Time.zone.now ? "open" : "closed",
        open_until: until_time&.iso8601,
        reason: Discourse.redis.get(REASON_KEY),
        consecutive_failures: Discourse.redis.get(FAILURE_KEY).to_i,
      }
    rescue StandardError => e
      Rails.logger.warn("[disify_email_protection] circuit state failed class=#{e.class}")
      { state: "closed", open_until: nil, reason: nil, consecutive_failures: 0 }
    end

    def open?
      until_time = open_until
      return false if until_time.blank?
      return true if until_time > Time.zone.now

      close_if_expired!
      false
    rescue StandardError => e
      Rails.logger.warn("[disify_email_protection] circuit read failed class=#{e.class}")
      false
    end

    def allow_request?
      !open?
    end

    def record_success!
      with_state_lock do
        until_time = open_until_without_lock
        reason = Discourse.redis.get(REASON_KEY).to_s

        # A late in-flight success must not defeat an explicit 429/quota backoff.
        next false if until_time.present? && until_time > Time.zone.now && PROTECTED_BACKOFF_REASONS.include?(reason)

        close_without_lock!
        true
      end
    rescue StandardError => e
      Rails.logger.warn("[disify_email_protection] circuit success update failed class=#{e.class}")
      false
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
      false
    end

    def reset!
      close!
    end

    def open_until
      open_until_without_lock
    rescue StandardError => e
      Rails.logger.warn("[disify_email_protection] circuit deadline read failed class=#{e.class}")
      nil
    end

    def open_for!(duration, reason)
      seconds = [duration.to_i, 1].max
      proposed_until = Time.zone.now.to_i + seconds

      with_state_lock do
        current_until = Discourse.redis.get(OPEN_UNTIL_KEY).to_i
        current_reason = Discourse.redis.get(REASON_KEY).to_s
        effective_until = [current_until, proposed_until].max

        # Never shorten an active window. Also preserve the strongest reason: a
        # 429/quota backoff must stay protected from a late success even when a
        # longer generic outage window was already open (or is opened later).
        effective_reason =
          if PROTECTED_BACKOFF_REASONS.include?(reason.to_s)
            reason.to_s
          elsif PROTECTED_BACKOFF_REASONS.include?(current_reason)
            current_reason
          else
            reason.to_s
          end

        ttl = [effective_until - Time.zone.now.to_i, 1].max
        Discourse.redis.setex(OPEN_UNTIL_KEY, ttl, effective_until)
        Discourse.redis.setex(REASON_KEY, ttl, effective_reason.first(64))
        Time.at(effective_until).in_time_zone
      end
    end

    def close!
      with_state_lock { close_without_lock! }
    rescue StandardError => e
      Rails.logger.warn("[disify_email_protection] circuit close failed class=#{e.class}")
      false
    end

    def close_if_expired!
      with_state_lock do
        until_time = open_until_without_lock
        close_without_lock! if until_time.present? && until_time <= Time.zone.now
      end
    end

    def open_until_without_lock
      raw = Discourse.redis.get(OPEN_UNTIL_KEY)
      return nil if raw.blank?

      Time.at(raw.to_i).in_time_zone
    end

    def close_without_lock!
      Discourse.redis.del(FAILURE_KEY, OPEN_UNTIL_KEY, REASON_KEY)
      true
    end

    def with_state_lock(&block)
      DistributedMutex.synchronize(STATE_MUTEX_KEY, validity: 10, &block)
    end
  end
end

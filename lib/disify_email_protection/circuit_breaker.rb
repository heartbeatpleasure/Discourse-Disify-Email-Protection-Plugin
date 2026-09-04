# frozen_string_literal: true

module ::DisifyEmailProtection
  module CircuitBreaker
    module_function

    PREFIX = "disify_email_protection:circuit"
    FAILURE_KEY = "#{PREFIX}:failures"
    OPEN_UNTIL_KEY = "#{PREFIX}:open_until"
    REASON_KEY = "#{PREFIX}:reason"
    PROTECTED_UNTIL_KEY = "#{PREFIX}:protected_until"
    PROTECTED_REASON_KEY = "#{PREFIX}:protected_reason"
    STATE_MUTEX_KEY = "disify-email-protection-circuit-state"
    FAILURE_WINDOW = 5.minutes
    DEFAULT_OPEN = 5.minutes
    PROTECTED_BACKOFF_REASONS = %w[rate_limited quota_exceeded].freeze

    def state
      until_time = open_until
      protected_until_time = protected_until
      protected_active = protected_until_time.present? && protected_until_time > Time.zone.now
      {
        state: until_time.present? && until_time > Time.zone.now ? "open" : "closed",
        open_until: until_time&.iso8601,
        reason:
          protected_active ? Discourse.redis.get(PROTECTED_REASON_KEY) : Discourse.redis.get(REASON_KEY),
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
        protected_until_time = protected_until_without_lock

        # A late in-flight success must not defeat the explicit Retry-After/quota
        # interval. Once that protected interval expires, a genuine success may
        # close any remaining generic outage window.
        next false if protected_until_time.present? && protected_until_time > Time.zone.now

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

    def protected_until
      protected_until_without_lock
    rescue StandardError => e
      Rails.logger.warn("[disify_email_protection] circuit protected deadline read failed class=#{e.class}")
      nil
    end

    def open_for!(duration, reason)
      seconds = [duration.to_i, 1].max
      proposed_until = Time.zone.now.to_i + seconds
      reason = reason.to_s.first(64)

      with_state_lock do
        current_until = Discourse.redis.get(OPEN_UNTIL_KEY).to_i
        current_reason = Discourse.redis.get(REASON_KEY).to_s

        if proposed_until >= current_until
          effective_until = proposed_until
          effective_reason = reason
        else
          effective_until = current_until
          effective_reason = current_reason
        end

        ttl = [effective_until - Time.zone.now.to_i, 1].max
        Discourse.redis.setex(OPEN_UNTIL_KEY, ttl, effective_until)
        Discourse.redis.setex(REASON_KEY, ttl, effective_reason)

        if PROTECTED_BACKOFF_REASONS.include?(reason)
          current_protected_until = Discourse.redis.get(PROTECTED_UNTIL_KEY).to_i
          protected_deadline = [current_protected_until, proposed_until].max
          protected_ttl = [protected_deadline - Time.zone.now.to_i, 1].max
          Discourse.redis.setex(PROTECTED_UNTIL_KEY, protected_ttl, protected_deadline)
          Discourse.redis.setex(PROTECTED_REASON_KEY, protected_ttl, reason)
        end

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

    def protected_until_without_lock
      raw = Discourse.redis.get(PROTECTED_UNTIL_KEY)
      return nil if raw.blank?

      Time.at(raw.to_i).in_time_zone
    end

    def close_without_lock!
      Discourse.redis.del(
        FAILURE_KEY,
        OPEN_UNTIL_KEY,
        REASON_KEY,
        PROTECTED_UNTIL_KEY,
        PROTECTED_REASON_KEY,
      )
      true
    end

    def with_state_lock(&block)
      DistributedMutex.synchronize(STATE_MUTEX_KEY, validity: 10, &block)
    end
  end
end

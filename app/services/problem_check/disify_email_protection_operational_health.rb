# frozen_string_literal: true

class ProblemCheck::DisifyEmailProtectionOperationalHealth < ProblemCheck
  self.priority = "high"
  self.perform_every = 10.minutes
  self.max_retries = 0
  self.max_blips = 1

  def run(&block)
    super(&block)
  ensure
    rearm_after_recovery
  end

  def call
    return no_problem unless SiteSetting.disify_email_protection_enabled

    payload = ::DisifyEmailProtection::Health.payload
    status = payload[:overall].to_s
    return no_problem if %w[healthy disabled].include?(status)

    reason = payload.dig(:provider, "last_error_code").presence ||
      payload.dig(:circuit_breaker, :reason).presence ||
      status

    problem(
      override_data: {
        status: ERB::Util.html_escape(status.humanize),
        reason: ERB::Util.html_escape(reason.to_s.humanize),
      },
      details: {
        status: status,
        reason: reason.to_s,
      },
    )
  rescue StandardError => e
    Rails.logger.warn("[disify_email_protection] problem check failed class=#{e.class}")
    no_problem
  end

  private

  def rearm_after_recovery
    tracker.watch! if tracker.passing? && tracker.ignored?
  rescue StandardError => e
    Rails.logger.warn("[disify_email_protection] problem check rearm failed class=#{e.class}")
  end
end

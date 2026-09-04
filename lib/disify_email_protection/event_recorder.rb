# frozen_string_literal: true

module ::DisifyEmailProtection
  module EventRecorder
    module_function

    EMAIL_HMAC_PATTERN = /\A[0-9a-f]{64}\z/.freeze

    def record!(email:, user:, flow:, mode:, decision:, reason:, confidence:, signals:, status:, latency_ms:, source:)
      record_from_fingerprint!(
        email_hmac: Normalizer.email_hmac(email),
        email_domain: Normalizer.domain(email),
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
    end

    def record_from_fingerprint!(
      email_hmac:,
      email_domain:,
      user:,
      flow:,
      mode:,
      decision:,
      reason:,
      confidence:,
      signals:,
      status:,
      latency_ms:,
      source:
    )
      hmac = email_hmac.to_s.downcase
      domain = email_domain.to_s.downcase
      return nil unless EMAIL_HMAC_PATTERN.match?(hmac)
      return nil unless PolicyExceptions.valid_domain?(domain)

      EmailEvent.create!(
        flow: flow.to_s.first(32),
        user_id: user&.persisted? ? user.id : nil,
        email_domain: domain,
        email_hmac: hmac,
        mode: mode.to_s.first(16),
        decision: decision.to_s.first(16),
        reason: reason.to_s.first(32),
        confidence: confidence,
        signals: Array(signals).filter_map { |signal| signal.to_s.strip.first(64).presence }.first(20),
        disify_status: status.to_s.first(24),
        latency_ms: latency_ms,
        source: source.to_s.first(16),
        occurred_at: Time.zone.now,
      )
    rescue StandardError => e
      Rails.logger.warn("[disify_email_protection] event record failed class=#{e.class}")
      nil
    end
  end
end

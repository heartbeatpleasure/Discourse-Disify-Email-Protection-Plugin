# frozen_string_literal: true

module ::DisifyEmailProtection
  module EventRecorder
    module_function

    def record!(email:, user:, flow:, mode:, decision:, reason:, confidence:, signals:, status:, latency_ms:, source:)
      EmailEvent.create!(
        flow: flow,
        user_id: user&.persisted? ? user.id : nil,
        email_domain: Normalizer.domain(email),
        email_hmac: Normalizer.email_hmac(email),
        mode: mode,
        decision: decision,
        reason: reason,
        confidence: confidence,
        signals: Array(signals).map(&:to_s).first(20),
        disify_status: status,
        latency_ms: latency_ms,
        source: source,
        occurred_at: Time.zone.now,
      )
    rescue StandardError => e
      Rails.logger.warn("[disify_email_protection] event record failed class=#{e.class}")
      nil
    end
  end
end

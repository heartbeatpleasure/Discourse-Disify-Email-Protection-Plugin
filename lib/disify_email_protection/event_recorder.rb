# frozen_string_literal: true

module ::DisifyEmailProtection
  module EventRecorder
    module_function

    def record!(email:, user:, flow:, mode:, decision:, reason:, confidence:, signals:, status:, latency_ms:, source:)
      EmailEvent.create!(
        flow: flow.to_s.first(32),
        user_id: user&.persisted? ? user.id : nil,
        email_domain: Normalizer.domain(email),
        email_hmac: Normalizer.email_hmac(email),
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

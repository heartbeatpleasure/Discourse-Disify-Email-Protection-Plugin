# frozen_string_literal: true

module ::DisifyEmailProtection
  module ReviewQueue
    module_function

    def create_or_refresh!(email:, user:, flow:, reason:, confidence:, signals:, metadata: {})
      return nil unless SiteSetting.disify_email_protection_review_queue_enabled

      hmac = Normalizer.email_hmac(email)
      domain = Normalizer.domain(email)
      scope = ReviewItem.pending.where(email_hmac: hmac, reason: reason.to_s)
      item = scope.order(id: :desc).first || ReviewItem.new
      item.user_id = user&.persisted? ? user.id : nil
      item.email_domain = domain
      item.email_hmac = hmac
      item.flow = flow
      item.reason = reason.to_s
      item.confidence = confidence
      item.signals = Array(signals).map(&:to_s).first(20)
      item.state = "pending"
      item.metadata = metadata.to_h.slice("source", "scan_id")
      item.save!
      item
    rescue StandardError => e
      Rails.logger.warn("[disify_email_protection] review item failed class=#{e.class}")
      nil
    end

    def approve!(item, actor)
      raise Discourse::InvalidParameters.new(:review) unless item.state == "pending"
      raise Discourse::InvalidParameters.new(:email_hmac) if item.email_hmac.blank?

      PolicyExceptions.create!(
        kind: "allow_email_hmac",
        value: item.email_hmac,
        actor: actor,
        reason: "Approved from email risk review ##{item.id}",
        expires_at: 7.days.from_now,
      )
      resolve!(item, "approved", actor)
    end

    def reject!(item, actor)
      raise Discourse::InvalidParameters.new(:review) unless item.state == "pending"

      if item.email_hmac.present?
        PolicyExceptions.create!(
          kind: "block_email_hmac",
          value: item.email_hmac,
          actor: actor,
          reason: "Rejected from email risk review ##{item.id}",
          expires_at: 30.days.from_now,
        )
      end
      resolve!(item, "rejected", actor)
    end

    def resolve!(item, state, actor)
      item.update!(state: state, resolved_by_id: actor.id, resolved_at: Time.zone.now)
      item
    end
  end
end

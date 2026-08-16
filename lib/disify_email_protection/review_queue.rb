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
      approve_with_policy!(
        item,
        actor,
        expires_at: 7.days.from_now,
        resolution: "allow_7_days",
        reason: "Approved for 7 days from email risk review ##{item.id}",
      )
    end

    def approve_permanently!(item, actor)
      approve_with_policy!(
        item,
        actor,
        expires_at: nil,
        resolution: "allow_permanent",
        reason: "Permanently approved from email risk review ##{item.id}",
      )
    end

    def reject!(item, actor)
      item.with_lock do
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
        resolve!(item, "rejected", actor, resolution: "block_30_days")
      end
    end

    def approve_with_policy!(item, actor, expires_at:, resolution:, reason:)
      item.with_lock do
        raise Discourse::InvalidParameters.new(:review) unless item.state == "pending"
        raise Discourse::InvalidParameters.new(:email_hmac) if item.email_hmac.blank?

        PolicyExceptions.create!(
          kind: "allow_email_hmac",
          value: item.email_hmac,
          actor: actor,
          reason: reason,
          expires_at: expires_at,
        )
        resolve!(item, "approved", actor, resolution: resolution)
      end
    end

    def resolve!(item, state, actor, resolution: nil)
      metadata = item.metadata.to_h.deep_stringify_keys
      metadata["resolution"] = resolution if resolution.present?

      item.update!(
        state: state,
        resolved_by_id: actor.id,
        resolved_at: Time.zone.now,
        metadata: metadata,
      )
      item
    end
  end
end

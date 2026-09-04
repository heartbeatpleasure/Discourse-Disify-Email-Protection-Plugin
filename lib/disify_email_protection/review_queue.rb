# frozen_string_literal: true

module ::DisifyEmailProtection
  module ReviewQueue
    module_function

    EMAIL_HMAC_PATTERN = /\A[0-9a-f]{64}\z/.freeze

    def enqueue_create_or_refresh!(email:, user:, flow:, reason:, confidence:, signals:, metadata: {})
      return false unless SiteSetting.disify_email_protection_review_queue_enabled

      hmac = Normalizer.email_hmac(email)
      domain = Normalizer.domain(email)
      return false if hmac.blank? || domain.blank?

      payload = {
        "email_hmac" => hmac,
        "email_domain" => domain,
        "user_id" => user&.persisted? ? user.id : nil,
        "flow" => flow.to_s.first(32),
        "reason" => reason.to_s.first(32),
        "confidence" => confidence,
        "signals" => Array(signals).filter_map { |signal| signal.to_s.strip.first(64).presence }.first(20),
        "metadata" => metadata.to_h.deep_stringify_keys.slice("source", "scan_id"),
        "current_site_id" => RailsMultisite::ConnectionManagement.current_db,
      }

      # Intentionally bypass Jobs.enqueue here. Discourse defers Jobs.enqueue until
      # the surrounding DB transaction commits, while a review decision deliberately
      # makes UserEmail validation fail and therefore rolls that transaction back.
      # Sidekiq receives only a non-reversible fingerprint and metadata, never raw email.
      Jobs::DisifyEmailProtectionCreateReview.perform_async(payload).present?
    rescue StandardError => e
      Rails.logger.warn("[disify_email_protection] review enqueue failed class=#{e.class}")
      false
    end

    def create_or_refresh!(email:, user:, flow:, reason:, confidence:, signals:, metadata: {})
      return nil unless SiteSetting.disify_email_protection_review_queue_enabled

      hmac = Normalizer.email_hmac(email)
      domain = Normalizer.domain(email)
      return nil if hmac.blank? || domain.blank?

      create_or_refresh_from_fingerprint!(
        email_hmac: hmac,
        email_domain: domain,
        user: user,
        flow: flow,
        reason: reason,
        confidence: confidence,
        signals: signals,
        metadata: metadata,
      )
    end

    def create_or_refresh_from_fingerprint!(
      email_hmac:,
      email_domain:,
      user:,
      flow:,
      reason:,
      confidence:,
      signals:,
      metadata: {}
    )
      hmac = email_hmac.to_s.downcase
      domain = email_domain.to_s.downcase
      return nil unless EMAIL_HMAC_PATTERN.match?(hmac)
      return nil unless PolicyExceptions.valid_domain?(domain)

      fresh_user = nil
      if user&.persisted?
        fresh_user = User.find_by(id: user.id)
        return nil if fresh_user.blank? || anonymized_user?(fresh_user)
      end

      normalized_reason = reason.to_s.first(32)
      return nil if normalized_reason.blank?

      mutex_key = "disify-email-protection-review-#{hmac.first(32)}-#{normalized_reason.first(32)}"
      DistributedMutex.synchronize(mutex_key, validity: 10) do
        scope = ReviewItem.pending.where(email_hmac: hmac, reason: normalized_reason)
        item = scope.order(id: :desc).first || ReviewItem.new
        item.user_id = fresh_user&.id
        item.email_domain = domain
        item.email_hmac = hmac
        item.flow = flow.to_s.first(32)
        item.reason = normalized_reason
        item.confidence = confidence
        item.signals = Array(signals).filter_map { |signal| signal.to_s.strip.first(64).presence }.first(20)
        item.state = "pending"
        item.metadata = metadata.to_h.deep_stringify_keys.slice("source", "scan_id")
        item.save!
        item
      end
    rescue StandardError => e
      Rails.logger.warn("[disify_email_protection] review item failed class=#{e.class}")
      nil
    end

    def anonymized_user?(user)
      suffix = defined?(::UserAnonymizer::EMAIL_SUFFIX) ? ::UserAnonymizer::EMAIL_SUFFIX.to_s : "@anonymized.invalid"
      user&.email.to_s.end_with?(suffix)
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
      ensure_admin_actor!(actor)
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
      ensure_admin_actor!(actor)
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

    def ensure_admin_actor!(actor)
      raise Discourse::InvalidAccess unless actor&.admin?
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

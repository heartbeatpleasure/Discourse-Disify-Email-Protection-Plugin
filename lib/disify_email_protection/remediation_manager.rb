# frozen_string_literal: true

module ::DisifyEmailProtection
  module RemediationManager
    module_function

    MANUAL_ELIGIBLE_REVIEW_REASONS = %w[disposable no_mx policy_block role].freeze
    BULK_ELIGIBLE_REVIEW_REASONS = %w[disposable no_mx policy_block].freeze
    VERIFY_RETRY_DELAY = 1.hour

    def active_for(user)
      return nil unless user&.id

      EmailRemediation.active.where(user_id: user.id).order(id: :desc).first
    end

    def remediation_for_review(item)
      return nil unless item&.id

      EmailRemediation.where(review_item_id: item.id).order(id: :desc).first
    end

    def eligible_existing_user_review?(item, allow_legacy_rejected: false)
      return false unless SiteSetting.disify_email_protection_existing_user_remediation_enabled
      return false unless item&.flow == "existing_user_scan"
      return false unless MANUAL_ELIGIBLE_REVIEW_REASONS.include?(item.reason.to_s)
      return false if item.user_id.blank? || item.email_hmac.blank?
      return true if item.state == "pending"

      allow_legacy_rejected && item.state == "rejected" &&
        item.metadata.to_h.deep_stringify_keys["resolution"] == "block_30_days"
    end

    def require_change!(item, actor, allow_legacy_rejected: false)
      ensure_admin_actor!(actor)
      raise Discourse::InvalidAccess unless SiteSetting.disify_email_protection_existing_user_remediation_enabled
      raise Discourse::InvalidParameters.new(:review) unless eligible_existing_user_review?(
        item,
        allow_legacy_rejected: allow_legacy_rejected,
      )

      remediation = nil
      UserLifecycle.with_active_user_id(item.user_id) do |fresh_user|
        raise Discourse::InvalidParameters.new(:user) if fresh_user.blank?
        raise Discourse::InvalidParameters.new(:review) unless email_hmac_matches?(item.email_hmac, fresh_user.email)

        item.with_lock do
          raise Discourse::InvalidParameters.new(:review) unless eligible_existing_user_review?(
            item,
            allow_legacy_rejected: allow_legacy_rejected,
          )

          existing = EmailRemediation.active.where(user_id: fresh_user.id).order(id: :desc).first
          raise Discourse::InvalidParameters.new(:remediation) if existing.present?

          now = Time.zone.now
          remediation = EmailRemediation.create!(
              user_id: fresh_user.id,
              review_item_id: item.id,
              required_by_id: actor.id,
              email_hmac: item.email_hmac,
              email_domain: item.email_domain,
              reason: item.reason,
              confidence: item.confidence,
              state: "required",
              active: true,
              required_at: now,
              enforce_at: now + grace_period_days.days,
            )

          metadata = item.metadata.to_h.deep_stringify_keys
          previous_resolution = metadata["resolution"]
          metadata["previous_resolution"] = previous_resolution if previous_resolution.present? && previous_resolution != "email_change_required"
          metadata["resolution"] = "email_change_required"
          metadata["remediation_id"] = remediation.id

          item.update!(
            state: "remediation",
            resolved_by_id: actor.id,
            resolved_at: Time.zone.now,
            metadata: metadata,
          )

          close_duplicate_pending_reviews!(
            user_id: fresh_user.id,
            email_hmac: item.email_hmac,
            except_id: item.id,
            actor_id: actor.id,
            remediation_id: remediation.id,
          )
        end
      end

      raise Discourse::InvalidParameters.new(:remediation) if remediation.blank?
      remediation
    end

    def cancel!(remediation, actor)
      ensure_admin_actor!(actor)
      raise Discourse::InvalidParameters.new(:remediation) unless remediation&.active?

      remediation.with_lock do
        raise Discourse::InvalidParameters.new(:remediation) unless remediation.active?

        remediation.update!(
          state: "cancelled",
          active: false,
          resolved_at: Time.zone.now,
          resolution: "cancelled_by_staff",
        )
      end

      if remediation.review_item_id.present?
        item = ReviewItem.find_by(id: remediation.review_item_id)
        if item.present?
          item.with_lock do
            metadata = item.metadata.to_h.deep_stringify_keys
            metadata["resolution"] = "email_change_cancelled"
            item.update!(metadata: metadata, resolved_by_id: actor.id, resolved_at: Time.zone.now)
          end
        end
      end

      remediation
    end

    def process_current_email!(user)
      return nil unless SiteSetting.disify_email_protection_enabled
      return nil unless SiteSetting.disify_email_protection_existing_user_remediation_enabled
      return nil if user.blank? || UserLifecycle.anonymized_user?(user)

      remediation = active_for(user)
      return nil if remediation.blank?

      current_email = user.email.to_s
      current_hmac = Normalizer.email_hmac(current_email)
      current_domain = Normalizer.domain(current_email)
      return nil if current_hmac.blank? || current_domain.blank?
      return remediation if email_hmac_matches?(remediation.email_hmac, current_email) && remediation.state == "required"

      result = Decision.evaluate(
        email: current_email,
        user: user,
        flow: "remediation_recheck",
        force_remote: false,
        dry_run: true,
        mode_override: "enforce",
      )

      if result.status == "unavailable" || result.decision == "fail_open"
        mark_verification_pending!(remediation, user, current_hmac, current_domain)
        schedule_verification!(remediation.id)
        return remediation.reload
      end

      if acceptable_result?(result)
        resolved = resolve_if_current!(
          remediation,
          user,
          current_hmac,
          resolution: "email_changed_verified",
        )
        if resolved
          UserNoteWriter.record!(
            user: user,
            reason: remediation.reason,
            domain: current_domain,
            confidence: remediation.confidence,
            context: "email-change remediation resolved",
          )
        end
        return remediation.reload
      end

      review_item = ReviewQueue.create_or_refresh!(
        email: current_email,
        user: user,
        flow: "existing_user_scan",
        reason: result.reason,
        confidence: result.confidence,
        signals: result.signals,
        metadata: { "source" => "remediation_recheck" },
      )

      if review_item.present?
        resolve_if_current!(
          remediation,
          user,
          current_hmac,
          resolution: "replacement_requires_review",
        )
      else
        # The replacement is known-risk but cannot be placed in review. Do not
        # immediately re-lock the account: start a fresh grace period for the new
        # current address so the user still has a path to recovery.
        reset_required_for_current!(remediation, user, current_hmac, current_domain, result)
      end

      remediation.reload
    rescue StandardError => e
      Rails.logger.warn("[disify_email_protection] remediation email processing failed class=#{e.class}")
      nil
    end

    def verify_pending!(remediation_id)
      remediation = EmailRemediation.active.find_by(id: remediation_id, state: "verification_pending")
      return false if remediation.blank?

      mutex_key = "disify-email-protection-remediation-verify-#{remediation.id}"
      DistributedMutex.synchronize(mutex_key, validity: 60) do
        remediation.reload
        next false unless remediation.active? && remediation.state == "verification_pending"

        user = User.find_by(id: remediation.user_id)
        next false if user.blank? || UserLifecycle.anonymized_user?(user)

        current_email = user.email.to_s
        current_hmac = Normalizer.email_hmac(current_email)
        expected_hmac = remediation.email_hmac.to_s
        if current_hmac.blank? || !secure_hmac_equal?(current_hmac, expected_hmac)
          Jobs.enqueue(:disify_email_protection_process_remediation_email_change, user_id: user.id)
          next false
        end

        result = Decision.evaluate(
          email: current_email,
          user: user,
          flow: "remediation_recheck",
          force_remote: false,
          dry_run: true,
          mode_override: "enforce",
        )

        if result.status == "unavailable" || result.decision == "fail_open"
          schedule_verification!(remediation.id)
          next false
        end

        if acceptable_result?(result)
          resolved = resolve_if_current!(
            remediation,
            user,
            expected_hmac,
            resolution: "email_changed_verified",
          )
          if resolved
            UserNoteWriter.record!(
              user: user,
              reason: remediation.reason,
              domain: remediation.email_domain,
              confidence: remediation.confidence,
              context: "email-change remediation resolved",
            )
          end
          next resolved
        end

        review_item = ReviewQueue.create_or_refresh!(
          email: current_email,
          user: user,
          flow: "existing_user_scan",
          reason: result.reason,
          confidence: result.confidence,
          signals: result.signals,
          metadata: { "source" => "remediation_recheck" },
        )

        if review_item.present?
          resolve_if_current!(
            remediation,
            user,
            expected_hmac,
            resolution: "replacement_requires_review",
          )
        else
          reset_required_for_current!(remediation, user, expected_hmac, Normalizer.domain(current_email), result)
        end
        true
      end
    rescue StandardError => e
      Rails.logger.warn("[disify_email_protection] remediation verification failed class=#{e.class}")
      current = EmailRemediation.active.find_by(id: remediation_id, state: "verification_pending")
      schedule_verification!(current.id) if current.present? && !UserLifecycle.anonymized_user?(current.user)
      false
    end

    def restriction_applies?(user, remediation = nil, now: Time.zone.now)
      return false unless SiteSetting.disify_email_protection_enabled
      return false unless SiteSetting.disify_email_protection_existing_user_remediation_enabled
      return false unless SiteSetting.disify_email_protection_remediation_after_grace.to_s == "restrict_account"
      return false if user.blank? || user.staff?
      return false unless self_service_email_change_available?(user)

      remediation ||= active_for(user)
      return false unless remediation&.active? && remediation.state == "required"
      return false unless remediation.enforce_at.present? && remediation.enforce_at <= now
      return false unless email_hmac_matches?(remediation.email_hmac, user.email)

      true
    end


    def self_service_email_change_available?(user)
      return false if user.blank?

      Guardian.new(user).can_edit_email?(user)
    rescue StandardError
      false
    end

    def public_payload(user)
      return nil unless SiteSetting.disify_email_protection_existing_user_remediation_enabled

      remediation = active_for(user)
      return nil if remediation.blank?
      return nil unless remediation.state == "required"
      return nil unless email_hmac_matches?(remediation.email_hmac, user.email)

      now = Time.zone.now
      {
        state: remediation.state,
        enforce_at: remediation.enforce_at&.iso8601,
        overdue: remediation.enforce_at.present? && remediation.enforce_at <= now,
        restricted: restriction_applies?(user, remediation, now: now),
        reason: remediation.reason,
        show_banner: SiteSetting.disify_email_protection_remediation_banner_enabled,
      }
    end

    def mark_restricted!(remediation, user)
      return false unless remediation&.active? && remediation.restricted_at.blank?
      return false unless restriction_applies?(user, remediation)

      updated = EmailRemediation.where(id: remediation.id, restricted_at: nil).update_all(
        restricted_at: Time.zone.now,
        updated_at: Time.zone.now,
      )
      updated == 1
    rescue StandardError
      false
    end

    def grace_period_days
      [[SiteSetting.disify_email_protection_remediation_grace_period_days.to_i, 1].max, 120].min
    end

    def bulk_candidate_scope(state)
      state = state.to_s
      return ReviewItem.none unless %w[pending rejected].include?(state)

      scope = ReviewItem.where(state: state, flow: "existing_user_scan", reason: BULK_ELIGIBLE_REVIEW_REASONS)
      if state == "rejected"
        scope = scope.where("metadata ->> 'resolution' = ?", "block_30_days")
      end
      scope.where.not(user_id: nil).where.not(email_hmac: nil)
    end


    def bulk_candidate_ids(state, limit: 1_000)
      limit = [[limit.to_i, 1].max, 1_000].min
      bulk_candidate_scope(state).order(:id).limit(limit).pluck(:id)
    end

    def email_hmac_matches?(expected_hmac, email)
      actual_hmac = Normalizer.email_hmac(email)
      secure_hmac_equal?(expected_hmac, actual_hmac)
    end

    def secure_hmac_equal?(left, right)
      left = left.to_s
      right = right.to_s
      return false if left.blank? || right.blank? || left.bytesize != right.bytesize

      ActiveSupport::SecurityUtils.secure_compare(left, right)
    end

    def schedule_verification!(remediation_id)
      remediation_id = Integer(remediation_id, exception: false)
      return false unless remediation_id&.positive?

      Jobs.enqueue_in(
        VERIFY_RETRY_DELAY,
        :disify_email_protection_verify_remediation,
        remediation_id: remediation_id,
      )
      true
    rescue StandardError => e
      Rails.logger.warn("[disify_email_protection] remediation verification enqueue failed class=#{e.class}")
      false
    end

    def acceptable_result?(result)
      result.status == "success" && !%w[block review].include?(result.decision.to_s)
    end

    def mark_verification_pending!(remediation, user, current_hmac, current_domain)
      UserLifecycle.with_active_user_id(user.id) do |fresh_user|
        next unless email_hmac_matches?(current_hmac, fresh_user.email)

        remediation.with_lock do
          next unless remediation.active?
          remediation.update!(
            email_hmac: current_hmac,
            email_domain: current_domain,
            state: "verification_pending",
            enforce_at: Time.zone.now + grace_period_days.days,
            restricted_at: nil,
          )
        end
      end
    end

    def resolve_if_current!(remediation, user, current_hmac, resolution:)
      resolved = false
      UserLifecycle.with_active_user_id(user.id) do |fresh_user|
        next unless email_hmac_matches?(current_hmac, fresh_user.email)

        remediation.with_lock do
          next unless remediation.active?
          remediation.update!(
            state: "resolved",
            active: false,
            resolved_at: Time.zone.now,
            resolution: resolution,
          )
          update_linked_review_resolution!(remediation, resolution)
          resolved = true
        end
      end
      resolved
    end

    def reset_required_for_current!(remediation, user, current_hmac, current_domain, result)
      UserLifecycle.with_active_user_id(user.id) do |fresh_user|
        next unless email_hmac_matches?(current_hmac, fresh_user.email)

        remediation.with_lock do
          next unless remediation.active?
          now = Time.zone.now
          remediation.update!(
            email_hmac: current_hmac,
            email_domain: current_domain,
            reason: result.reason.to_s.first(32),
            confidence: result.confidence,
            state: "required",
            enforce_at: now + grace_period_days.days,
            restricted_at: nil,
            notified_at: nil,
            reminder_sent_at: nil,
          )
        end
      end
    end

    def update_linked_review_resolution!(remediation, resolution)
      return if remediation.review_item_id.blank?

      item = ReviewItem.find_by(id: remediation.review_item_id)
      return if item.blank?

      metadata = item.metadata.to_h.deep_stringify_keys
      metadata["resolution"] =
        case resolution.to_s
        when "email_changed_verified"
          "email_change_resolved"
        when "replacement_requires_review"
          "replacement_requires_review"
        else
          metadata["resolution"]
        end
      item.update!(metadata: metadata, resolved_at: Time.zone.now)
    end

    def close_duplicate_pending_reviews!(user_id:, email_hmac:, except_id:, actor_id:, remediation_id:)
      ReviewItem
        .pending
        .where(user_id: user_id, email_hmac: email_hmac, flow: "existing_user_scan")
        .where.not(id: except_id)
        .order(:id)
        .each do |duplicate|
          duplicate.with_lock do
            next unless duplicate.state == "pending"

            metadata = duplicate.metadata.to_h.deep_stringify_keys
            metadata["resolution"] = "superseded_by_email_change_requirement"
            metadata["remediation_id"] = remediation_id
            duplicate.update!(
              state: "expired",
              resolved_by_id: actor_id,
              resolved_at: Time.zone.now,
              metadata: metadata,
            )
          end
        end
    end

    def ensure_admin_actor!(actor)
      raise Discourse::InvalidAccess unless actor&.admin?
    end
  end
end

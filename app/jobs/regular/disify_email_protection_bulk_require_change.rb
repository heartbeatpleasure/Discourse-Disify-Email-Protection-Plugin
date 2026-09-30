# frozen_string_literal: true

module Jobs
  class DisifyEmailProtectionBulkRequireChange < ::Jobs::Base
    def execute(args)
      return unless SiteSetting.disify_email_protection_bulk_remediation_enabled
      return unless SiteSetting.disify_email_protection_existing_user_remediation_enabled

      actor_id = Integer(args[:actor_id], exception: false)
      state = args[:state].to_s
      return unless actor_id&.positive? && %w[pending rejected].include?(state)

      actor = User.find_by(id: actor_id)
      return unless actor&.admin?

      allow_legacy_rejected = state == "rejected"
      review_ids = Array(args[:review_ids]).filter_map { |value| Integer(value, exception: false) }.select(&:positive?).uniq.first(1_000)

      review_ids.each do |review_id|
        item = ::DisifyEmailProtection::ReviewItem.includes(user: :primary_email).find_by(id: review_id)
        next if item.blank?
        next unless ::DisifyEmailProtection::RemediationManager.eligible_existing_user_review?(
          item,
          allow_legacy_rejected: allow_legacy_rejected,
        )

        begin
          remediation = ::DisifyEmailProtection::RemediationManager.require_change!(
            item,
            actor,
            allow_legacy_rejected: allow_legacy_rejected,
          )
          next if remediation.blank?

          ::DisifyEmailProtection::RemediationNotifier.notify_required!(remediation)
          ::DisifyEmailProtection::UserNoteWriter.record!(
            user: remediation.user,
            reason: remediation.reason,
            domain: remediation.email_domain,
            confidence: remediation.confidence,
            context: "email change required by staff",
          )
          ::DisifyEmailProtection::StaffAudit.log!(
            actor: actor,
            action: "remediation_required",
            details: { review_id: item.id, remediation_id: remediation.id, user_id: remediation.user_id },
          )
        rescue Discourse::InvalidParameters, Discourse::InvalidAccess, ActiveRecord::RecordNotUnique
          # Expected stale/duplicate cases are skipped so one changed account cannot stop the batch.
          next
        end
      end
    end
  end
end

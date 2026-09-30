# frozen_string_literal: true

module Jobs
  class DisifyEmailProtectionRemediationMaintenance < ::Jobs::Scheduled
    every 1.day

    BATCH_SIZE = 100

    def execute(_args)
      return unless SiteSetting.disify_email_protection_enabled
      return unless SiteSetting.disify_email_protection_existing_user_remediation_enabled

      ::DisifyEmailProtection::EmailRemediation
        .required
        .includes(user: :primary_email)
        .find_each(batch_size: BATCH_SIZE) do |remediation|
        user = remediation.user
        next if user.blank? || ::DisifyEmailProtection::UserLifecycle.anonymized_user?(user)

        unless ::DisifyEmailProtection::RemediationManager.email_hmac_matches?(remediation.email_hmac, user.email)
          Jobs.enqueue(:disify_email_protection_process_remediation_email_change, user_id: user.id)
          next
        end

        if remediation.notified_at.blank?
          ::DisifyEmailProtection::RemediationNotifier.notify_required!(remediation)
        elsif ::DisifyEmailProtection::RemediationNotifier.reminder_due?(remediation)
          ::DisifyEmailProtection::RemediationNotifier.notify_reminder!(remediation)
        end
      end

      ::DisifyEmailProtection::EmailRemediation.verification_pending.find_each(batch_size: BATCH_SIZE) do |remediation|
        Jobs.enqueue(
          :disify_email_protection_verify_remediation,
          remediation_id: remediation.id,
        )
      end
    end
  end
end

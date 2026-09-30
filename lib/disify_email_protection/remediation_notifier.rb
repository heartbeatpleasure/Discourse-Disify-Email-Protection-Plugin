# frozen_string_literal: true

module ::DisifyEmailProtection
  module RemediationNotifier
    module_function

    REMINDER_WINDOW = 7.days

    def notify_required!(remediation)
      send_message!(remediation, reminder: false)
    end

    def notify_reminder!(remediation)
      send_message!(remediation, reminder: true)
    end

    def reminder_due?(remediation, now: Time.zone.now)
      return false unless remediation&.active? && remediation.state == "required"
      return false if remediation.reminder_sent_at.present?
      return false if remediation.enforce_at.blank? || remediation.enforce_at <= now

      remediation.enforce_at <= now + REMINDER_WINDOW
    end

    def send_message!(remediation, reminder:)
      return false unless SiteSetting.disify_email_protection_remediation_user_pm_enabled
      return false unless remediation&.active? && remediation.state == "required"

      mutex_key = "disify-email-protection-remediation-notify-#{remediation.id}-#{reminder ? 'reminder' : 'initial'}"
      DistributedMutex.synchronize(mutex_key, validity: 30) do
        remediation.reload
        timestamp_field = reminder ? :reminder_sent_at : :notified_at
        next false if remediation.public_send(timestamp_field).present?
        next false unless remediation.active? && remediation.state == "required"

        user = User.find_by(id: remediation.user_id)
        next false if user.blank? || UserLifecycle.anonymized_user?(user)

        deadline = I18n.l(remediation.enforce_at.to_date, format: :long)
        email_path = "/u/#{user.encoded_username}/preferences/email"
        key = reminder ? "remediation.user_pm.reminder" : "remediation.user_pm.required"

        PostCreator.create!(
          Discourse.system_user,
          archetype: Archetype.private_message,
          target_usernames: user.username,
          title: I18n.t("disify_email_protection.#{key}.title"),
          raw: I18n.t(
            "disify_email_protection.#{key}.body",
            deadline: deadline,
            email_path: email_path,
          ),
        )

        remediation.update_column(timestamp_field, Time.zone.now)
        true
      end
    rescue StandardError => e
      Rails.logger.warn("[disify_email_protection] remediation notification failed class=#{e.class}")
      false
    end
  end
end

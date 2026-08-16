# frozen_string_literal: true

module ::DisifyEmailProtection
  module ReviewQueueNotifier
    module_function

    LAST_SENT_KEY = "review_queue_notification_last_sent"
    MUTEX_KEY = "disify-email-protection-review-queue-notification"
    RECIPIENT_GROUPS = {
      "admins" => :admins,
      "staff" => :staff,
    }.freeze

    def send_if_needed!
      return false unless SiteSetting.disify_email_protection_enabled
      return false unless SiteSetting.disify_email_protection_review_queue_enabled
      return false unless SiteSetting.disify_email_protection_review_queue_notification_enabled

      DistributedMutex.synchronize(MUTEX_KEY, validity: 30) do
        next false unless reminder_due?

        pending = ReviewItem.pending.count
        next false if pending.zero?

        group = recipient_group
        next false if group.blank?
        next false unless group.human_users.exists?

        PostCreator.create!(
          Discourse.system_user,
          target_group_names: [group.name],
          archetype: Archetype.private_message,
          title: I18n.t("disify_email_protection.review_queue_notification.title"),
          raw: I18n.t(
            "disify_email_protection.review_queue_notification.body",
            count: pending,
          ),
        )

        PluginStore.set(STORE_NAMESPACE, LAST_SENT_KEY, Time.zone.now.iso8601)
        true
      end
    rescue StandardError => e
      Rails.logger.warn("[disify_email_protection] review queue notification failed class=#{e.class}")
      false
    end

    def reminder_due?
      last_sent = parse_time(PluginStore.get(STORE_NAMESPACE, LAST_SENT_KEY))
      return true if last_sent.blank?

      last_sent <= interval_days.days.ago
    end

    def interval_days
      [[SiteSetting.disify_email_protection_review_queue_notification_interval_days.to_i, 1].max, 365].min
    end

    def recipient_group
      scope = SiteSetting.disify_email_protection_review_queue_notification_recipients.to_s
      group_key = RECIPIENT_GROUPS[scope]
      return nil if group_key.blank?

      Group[group_key]
    end

    def parse_time(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end

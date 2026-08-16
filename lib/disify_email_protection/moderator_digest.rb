# frozen_string_literal: true

module ::DisifyEmailProtection
  module ModeratorDigest
    module_function

    LAST_SENT_KEY = "moderator_digest_last_sent"

    def send_if_needed!
      return false unless SiteSetting.disify_email_protection_enabled
      return false unless SiteSetting.disify_email_protection_moderator_digest_enabled

      group_name = SiteSetting.disify_email_protection_moderator_digest_group.to_s.strip.first(100)
      return false if group_name.blank?

      group = Group.find_by("lower(name) = ?", group_name.downcase)
      return false if group.blank?

      since = 24.hours.ago
      events = EmailEvent.where("occurred_at >= ?", since)
      pending = ReviewItem.pending.count
      blocked = events.where(decision: "block").count
      reviewed = events.where(decision: "review").count
      failures = events.where(disify_status: "unavailable").count

      # Pending items alone are handled by the configurable review-queue reminder.
      # The daily digest should represent new/recent activity, not repeat the same
      # unresolved queue state every day.
      return false if blocked < 10 && failures.zero? && reviewed.zero?

      title = "Email risk protection summary"
      raw = <<~MD
        Summary for the last 24 hours:

        - Checked events: #{events.count}
        - Blocked attempts: #{blocked}
        - Review decisions: #{reviewed}
        - Pending review items: #{pending}
        - External validation failures: #{failures}
        - Current health: #{Health.payload[:overall].to_s.humanize}

        Review details in **Admin > Plugins > Disposable Email Protection**.
      MD

      PostCreator.create!(
        Discourse.system_user,
        target_group_names: [group.name],
        archetype: Archetype.private_message,
        title: title,
        raw: raw,
      )
      PluginStore.set(STORE_NAMESPACE, LAST_SENT_KEY, Time.zone.now.iso8601)
      true
    rescue StandardError => e
      Rails.logger.warn("[disify_email_protection] moderator digest failed class=#{e.class}")
      false
    end
  end
end

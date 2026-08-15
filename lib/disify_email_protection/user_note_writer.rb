# frozen_string_literal: true

module ::DisifyEmailProtection
  module UserNoteWriter
    module_function

    NOTE_NAMESPACE = "disify_email_protection_notes"

    def record!(user:, reason:, domain:, confidence:, context:)
      return false unless SiteSetting.disify_email_protection_user_notes_enabled
      return false unless user&.persisted?
      return false unless defined?(::DiscourseUserNotes)
      return false unless SiteSetting.respond_to?(:user_notes_enabled) && SiteSetting.user_notes_enabled

      key = "#{user.id}:#{reason}:#{domain}:#{context}"
      last = PluginStore.get(NOTE_NAMESPACE, key)
      return false if last.present? && Time.zone.parse(last.to_s) > 24.hours.ago

      note = "Email risk protection: #{context}. Reason: #{reason}. Domain: #{domain}."
      note += " Confidence: #{confidence}." if confidence.present?
      ::DiscourseUserNotes.add_note(user, note, Discourse::SYSTEM_USER_ID)
      PluginStore.set(NOTE_NAMESPACE, key, Time.zone.now.iso8601)
      true
    rescue StandardError => e
      Rails.logger.warn("[disify_email_protection] user note failed class=#{e.class}")
      false
    end
  end
end

# frozen_string_literal: true

module ::DisifyEmailProtection
  module UserNoteWriter
    module_function

    NOTE_NAMESPACE = "disify_email_protection_notes"
    DEBOUNCE_TTL = 24.hours
    CLEANUP_BATCH_SIZE = 1_000

    def record!(user:, reason:, domain:, confidence:, context:)
      return false unless SiteSetting.disify_email_protection_user_notes_enabled
      return false unless user&.persisted?
      return false unless defined?(::DiscourseUserNotes)
      return false unless SiteSetting.respond_to?(:user_notes_enabled) && SiteSetting.user_notes_enabled

      result =
        UserLifecycle.with_active_user(user) do |fresh_user|
          key = "#{fresh_user.id}:#{reason}:#{domain}:#{context}"
          last = PluginStore.get(NOTE_NAMESPACE, key)
          next false if recent_timestamp?(last)

          note = "Email risk protection: #{context}. Reason: #{reason}. Domain: #{domain}."
          note += " Confidence: #{confidence}." if confidence.present?
          ::DiscourseUserNotes.add_note(fresh_user, note, Discourse::SYSTEM_USER_ID)
          PluginStore.set(NOTE_NAMESPACE, key, Time.zone.now.iso8601)
          true
        end

      result == true
    rescue StandardError => e
      Rails.logger.warn("[disify_email_protection] user note failed class=#{e.class}")
      false
    end


    def cleanup_stale_debounce!(now: Time.zone.now)
      return 0 unless defined?(::PluginStoreRow)

      cutoff = now - DEBOUNCE_TTL
      deleted = 0
      PluginStoreRow.where(plugin_name: NOTE_NAMESPACE).in_batches(of: CLEANUP_BATCH_SIZE) do |batch|
        stale_ids =
          batch.pluck(:id, :value).filter_map do |id, value|
            timestamp = Time.zone.parse(value.to_s)
            id if timestamp.blank? || timestamp <= cutoff
          rescue ArgumentError, TypeError
            id
          end

        deleted += PluginStoreRow.where(id: stale_ids).delete_all if stale_ids.present?
      end
      deleted
    end

    def recent_timestamp?(value)
      return false if value.blank?

      parsed = Time.zone.parse(value.to_s)
      parsed.present? && parsed > DEBOUNCE_TTL.ago
    rescue ArgumentError, TypeError
      false
    end
  end
end

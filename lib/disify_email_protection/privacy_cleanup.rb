# frozen_string_literal: true

module ::DisifyEmailProtection
  module PrivacyCleanup
    module_function

    USER_NOTE_PREFIX = "Email risk protection:"

    def anonymize_user!(user)
      return false unless user&.id

      user_id = user.id
      email_hmacs =
        (
          EmailEvent.where(user_id: user_id).where.not(email_hmac: nil).pluck(:email_hmac) +
            ReviewItem.where(user_id: user_id).where.not(email_hmac: nil).pluck(:email_hmac)
        ).uniq

      EmailEvent.transaction do
        EmailEvent.where(user_id: user_id).update_all(
          user_id: nil,
          email_domain: nil,
          email_hmac: nil,
        )
        ReviewItem.where(user_id: user_id).delete_all

        if email_hmacs.present?
          # Exact-email policy exceptions are site-wide administrative policy, not
          # user-owned records. Removing them because one account is anonymized can
          # silently undo a deliberate allow/block rule that also matters elsewhere.
          EmailCheck.where(cache_key: email_hmacs.map { |hmac| "email:#{hmac}" }).delete_all
        end
      end

      clear_plugin_note_state!(user_id)
      clear_disify_user_notes!(user)
      true
    rescue StandardError => e
      Rails.logger.warn("[disify_email_protection] anonymization cleanup failed class=#{e.class}")
      false
    end

    def clear_plugin_note_state!(user_id)
      return unless defined?(::PluginStoreRow)

      PluginStoreRow
        .where(plugin_name: UserNoteWriter::NOTE_NAMESPACE)
        .where("key LIKE ?", "#{user_id}:%")
        .delete_all
    end

    def clear_disify_user_notes!(user)
      return unless defined?(::DiscourseUserNotes)
      return unless ::DiscourseUserNotes.respond_to?(:notes_for) && ::DiscourseUserNotes.respond_to?(:remove_note)

      Array(::DiscourseUserNotes.notes_for(user.id)).each do |note|
        raw = note[:raw] || note["raw"]
        note_id = note[:id] || note["id"]
        next unless raw.to_s.start_with?(USER_NOTE_PREFIX) && note_id.present?

        ::DiscourseUserNotes.remove_note(user, note_id)
      end
    end
  end
end

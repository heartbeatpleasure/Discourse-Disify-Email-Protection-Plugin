# frozen_string_literal: true

module Jobs
  class DisifyEmailProtectionCreateReview < ::Jobs::Base
    def execute(args)
      user_id = Integer(args[:user_id], exception: false)
      user = user_id&.positive? ? User.find_by(id: user_id) : nil

      # A queued validation review may run after the account was deleted or
      # anonymized. Never recreate old identifying fingerprints in that case.
      if user_id&.positive?
        return if user.blank? || ::DisifyEmailProtection::ReviewQueue.anonymized_user?(user)
      end

      item =
        ::DisifyEmailProtection::ReviewQueue.create_or_refresh_from_fingerprint!(
          email_hmac: args[:email_hmac],
          email_domain: args[:email_domain],
          user: user,
          flow: args[:flow],
          reason: args[:reason],
          confidence: args[:confidence],
          signals: args[:signals],
          metadata: args[:metadata],
        )

      raise "DISIFY email-protection review materialization failed" if item.blank?

      if item.user.present?
        ::DisifyEmailProtection::UserNoteWriter.record!(
          user: item.user,
          reason: item.reason,
          domain: item.email_domain,
          confidence: item.confidence,
          context: "review item created",
        )
      end
    end
  end
end

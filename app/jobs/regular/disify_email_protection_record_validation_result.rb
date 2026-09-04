# frozen_string_literal: true

module Jobs
  class DisifyEmailProtectionRecordValidationResult < ::Jobs::Base
    def execute(args)
      user_id = Integer(args[:user_id], exception: false)
      user = user_id&.positive? ? User.find_by(id: user_id) : nil
      user_is_stale =
        user_id&.positive? &&
          (user.blank? || ::DisifyEmailProtection::ReviewQueue.anonymized_user?(user))

      counters =
        ::DisifyEmailProtection::Statistics::COUNTERS.index_with do |key|
          [args.dig(:counters, key).to_i, 0].max
        end
      ::DisifyEmailProtection::Statistics.increment!(counters)

      # Aggregate statistics contain no user/email identifiers and remain useful
      # even if the user disappeared before this delayed write. Do not recreate an
      # identifying event or note after deletion/anonymization, though.
      return if user_is_stale

      ::DisifyEmailProtection::EventRecorder.record_from_fingerprint!(
        email_hmac: args[:email_hmac],
        email_domain: args[:email_domain],
        user: user,
        flow: args[:flow],
        mode: args[:mode],
        decision: args[:decision],
        reason: args[:reason],
        confidence: args[:confidence],
        signals: args[:signals],
        status: args[:status],
        latency_ms: args[:latency_ms],
        source: args[:source],
      )

      if user.present? && args[:decision].to_s == "block"
        ::DisifyEmailProtection::UserNoteWriter.record!(
          user: user,
          reason: args[:reason],
          domain: args[:email_domain],
          confidence: args[:confidence],
          context: "email change blocked",
        )
      end
    end
  end
end

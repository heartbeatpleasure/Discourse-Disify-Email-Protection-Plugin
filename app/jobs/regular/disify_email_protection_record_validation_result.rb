# frozen_string_literal: true

module Jobs
  class DisifyEmailProtectionRecordValidationResult < ::Jobs::Base
    def execute(args)
      user_id = Integer(args[:user_id], exception: false)

      if user_id&.positive?
        ::DisifyEmailProtection::UserLifecycle.with_active_user_id(user_id) do |user|
          persist_identifying_result(args, user)
        end
      else
        persist_identifying_result(args, nil)
      end

      counters =
        ::DisifyEmailProtection::Statistics::COUNTERS.index_with do |key|
          [args.dig(:counters, key).to_i, 0].max
        end
      ::DisifyEmailProtection::Statistics.increment!(counters)
    end

    private

    def persist_identifying_result(args, user)
      persist_durable_cache(args)

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

    def persist_durable_cache(args)
      cache = args[:cache].to_h.deep_stringify_keys
      result = ::DisifyEmailProtection::Cache.persistable_result(cache["result"])
      return if result.blank?

      if cache["domain"] == true
        ::DisifyEmailProtection::Cache.write_domain(args[:email_domain], result)
      end
      if cache["email"] == true
        ::DisifyEmailProtection::Cache.write_email_fingerprint(
          email_hmac: args[:email_hmac],
          email_domain: args[:email_domain],
          result: result,
        )
      end
    end
  end
end

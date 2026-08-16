# frozen_string_literal: true

module Jobs
  class DisifyEmailProtectionReviewQueueNotification < ::Jobs::Scheduled
    every 1.day

    def execute(_args)
      ::DisifyEmailProtection::ReviewQueueNotifier.send_if_needed!
    end
  end
end

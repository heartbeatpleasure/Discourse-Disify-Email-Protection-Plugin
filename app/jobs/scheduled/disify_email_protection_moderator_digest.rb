# frozen_string_literal: true

module Jobs
  class DisifyEmailProtectionModeratorDigest < ::Jobs::Scheduled
    every 1.day

    def execute(_args)
      ::DisifyEmailProtection::ModeratorDigest.send_if_needed!
    end
  end
end

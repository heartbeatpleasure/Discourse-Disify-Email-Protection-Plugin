# frozen_string_literal: true

module Jobs
  class DisifyEmailProtectionHealthCheck < ::Jobs::Scheduled
    every 6.hours

    def execute(_args)
      ::DisifyEmailProtection::Health.scheduled_test!
    end
  end
end

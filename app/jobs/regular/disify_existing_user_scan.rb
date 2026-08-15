# frozen_string_literal: true

module Jobs
  class DisifyExistingUserScan < ::Jobs::Base
    def execute(args)
      ::DisifyEmailProtection::ExistingUserScan.process_batch!(args[:scan_id].to_s)
    end
  end
end

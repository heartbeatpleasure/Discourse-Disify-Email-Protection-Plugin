# frozen_string_literal: true

module Jobs
  class DisifyExistingUserScan < ::Jobs::Base
    SCAN_ID_PATTERN = /\A[0-9a-f]{16}\z/.freeze

    def execute(args)
      scan_id = args[:scan_id].to_s
      return unless SCAN_ID_PATTERN.match?(scan_id)

      ::DisifyEmailProtection::ExistingUserScan.process_batch!(scan_id)
    end
  end
end

# frozen_string_literal: true

module Jobs
  class DisifyEmailProtectionVerifyRemediation < ::Jobs::Base
    def execute(args)
      remediation_id = Integer(args[:remediation_id], exception: false)
      return unless remediation_id&.positive?

      ::DisifyEmailProtection::RemediationManager.verify_pending!(remediation_id)
    end
  end
end

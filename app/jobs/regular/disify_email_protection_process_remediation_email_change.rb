# frozen_string_literal: true

module Jobs
  class DisifyEmailProtectionProcessRemediationEmailChange < ::Jobs::Base
    def execute(args)
      user_id = Integer(args[:user_id], exception: false)
      return unless user_id&.positive?

      user = User.find_by(id: user_id)
      return if user.blank?

      ::DisifyEmailProtection::RemediationManager.process_current_email!(user)
    end
  end
end

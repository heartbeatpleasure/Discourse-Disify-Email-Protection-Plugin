# frozen_string_literal: true

module Jobs
  class DisifyEmailProtectionAnonymizeCleanup < ::Jobs::Base
    def execute(args)
      user_id = Integer(args[:user_id], exception: false)
      return if user_id.blank? || user_id <= 0

      user = User.find_by(id: user_id)
      return if user.blank?
      return if ::DisifyEmailProtection::PrivacyCleanup.anonymize_user!(user)

      raise "DISIFY email-protection anonymization cleanup failed"
    end
  end
end

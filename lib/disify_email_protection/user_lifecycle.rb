# frozen_string_literal: true

module ::DisifyEmailProtection
  module UserLifecycle
    module_function

    def anonymized_user?(user)
      suffix =
        defined?(::UserAnonymizer::EMAIL_SUFFIX) ? ::UserAnonymizer::EMAIL_SUFFIX.to_s : "@anonymized.invalid"
      user&.email.to_s.end_with?(suffix)
    end

    def with_active_user(user)
      return yield(nil) unless user&.persisted?

      result = nil
      User.transaction do
        locked_user = User.lock.find_by(id: user.id)
        next if locked_user.blank? || anonymized_user?(locked_user)

        result = yield(locked_user)
      end
      result
    end

    def with_active_user_id(user_id)
      id = Integer(user_id, exception: false)
      return nil unless id&.positive?

      result = nil
      User.transaction do
        locked_user = User.lock.find_by(id: id)
        next if locked_user.blank? || anonymized_user?(locked_user)

        result = yield(locked_user)
      end
      result
    end
  end
end

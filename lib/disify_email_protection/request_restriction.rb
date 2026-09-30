# frozen_string_literal: true

module ::DisifyEmailProtection
  module RequestRestriction
    module_function

    SAFE_HTTP_METHODS = %w[GET HEAD OPTIONS].freeze
    # Keep every request needed to recover the account/email path usable after
    # the grace period. `confirm_session` / `list_second_factors` are part of
    # Discourse's trusted-session flow and can be required before an email may
    # be edited. Do not make a remediation self-locking by blocking them.
    ALLOWED_USER_ACTIONS = %w[
      update_primary_email
      destroy_email
      confirm_session
      trusted_session
      list_second_factors
    ].freeze

    def enforce!(controller)
      user = controller.current_user
      return false if user.blank? || user.staff?
      return false if SAFE_HTTP_METHODS.include?(controller.request.request_method)

      remediation = RemediationManager.active_for(user)
      return false unless RemediationManager.restriction_applies?(user, remediation)
      return false if allowed_recovery_request?(controller)

      if RemediationManager.mark_restricted!(remediation, user)
        UserNoteWriter.record!(
          user: user,
          reason: remediation.reason,
          domain: remediation.email_domain,
          confidence: remediation.confidence,
          context: "email-change remediation reached restricted mode",
        )
      end

      message = I18n.t("disify_email_protection.remediation.restricted_error")
      if controller.request.format.json? || controller.request.xhr?
        controller.render(
          json: { errors: [message], error_type: "email_change_required" },
          status: :forbidden,
        )
      else
        controller.flash[:error] = message
        controller.redirect_to(
          "#{Discourse.base_path}/u/#{user.encoded_username}/preferences/email",
        )
      end
      true
    end

    def allowed_recovery_request?(controller)
      return true if controller.is_a?(::UsersEmailController)
      return true if controller.is_a?(::SessionController)

      controller.is_a?(::UsersController) && ALLOWED_USER_ACTIONS.include?(controller.action_name.to_s)
    end
  end
end

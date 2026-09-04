# frozen_string_literal: true

# name: Discourse-Disify-Email-Protection-Plugin
# about: Adds disposable-email and deliverability protection to Discourse using DISIFY.
# version: 0.1.19
# authors: Chris

add_admin_route "admin.disify_email_protection.title", "disifyEmailProtection"

enabled_site_setting :disify_email_protection_enabled

module ::DisifyEmailProtection
  PLUGIN_NAME = "Discourse-Disify-Email-Protection-Plugin"
  PLUGIN_VERSION = "0.1.19"
  API_BASE_URL = "https://disify.com/api"
  STORE_NAMESPACE = "disify_email_protection"
  TRUSTED_ALIAS_DOMAINS = %w[
    gmail.com googlemail.com outlook.com hotmail.com live.com msn.com
    icloud.com me.com mac.com
  ].freeze
end

after_initialize do
  begin
    Rails.application.config.filter_parameters |= [
      :disify_email_protection_api_key,
      :disify_email_protection_exception_value,
      :email,
      :new_email,
    ]
  rescue StandardError
    # Keep plugin boot resilient if filter configuration is unavailable.
  end

  require_dependency File.expand_path("app/models/disify_email_protection/email_check.rb", __dir__)
  require_dependency File.expand_path("app/models/disify_email_protection/email_event.rb", __dir__)
  require_dependency File.expand_path("app/models/disify_email_protection/review_item.rb", __dir__)
  require_dependency File.expand_path("app/models/disify_email_protection/daily_stat.rb", __dir__)
  require_dependency File.expand_path("app/models/disify_email_protection/policy_exception.rb", __dir__)
  require_dependency File.expand_path("app/controllers/disify_email_protection/admin_controller.rb", __dir__)

  require_relative "lib/disify_email_protection/normalizer"
  require_relative "lib/disify_email_protection/client"
  require_relative "lib/disify_email_protection/circuit_breaker"
  require_relative "lib/disify_email_protection/health"
  require_relative "lib/disify_email_protection/cache"
  require_relative "lib/disify_email_protection/statistics"
  require_relative "lib/disify_email_protection/user_lifecycle"
  require_relative "lib/disify_email_protection/event_recorder"
  require_relative "lib/disify_email_protection/policy_exceptions"
  require_relative "lib/disify_email_protection/review_queue"
  require_relative "lib/disify_email_protection/user_note_writer"
  require_relative "lib/disify_email_protection/privacy_cleanup"
  require_relative "lib/disify_email_protection/staff_audit"
  require_relative "lib/disify_email_protection/decision"
  require_relative "lib/disify_email_protection/existing_user_scan"
  require_relative "lib/disify_email_protection/moderator_digest"
  require_relative "lib/disify_email_protection/review_queue_notifier"

  require_relative "app/jobs/regular/disify_existing_user_scan"
  require_relative "app/jobs/regular/disify_email_protection_create_review"
  require_relative "app/jobs/regular/disify_email_protection_record_validation_result"
  require_relative "app/jobs/regular/disify_email_protection_anonymize_cleanup"
  require_relative "app/jobs/scheduled/disify_email_protection_cleanup"
  require_relative "app/jobs/scheduled/disify_email_protection_health_check"
  require_relative "app/jobs/scheduled/disify_email_protection_moderator_digest"
  require_relative "app/jobs/scheduled/disify_email_protection_review_queue_notification"

  require_relative "app/services/problem_check/disify_email_protection_operational_health"
  register_problem_check ProblemCheck::DisifyEmailProtectionOperationalHealth

  validate("UserEmail", :disify_email_protection_validation) do
    next if !SiteSetting.disify_email_protection_enabled
    next if email.blank? || !will_save_change_to_email?

    user_record = user
    staged_check_enabled =
      user_record&.staged? && SiteSetting.disify_email_protection_check_staged_users &&
        !(user_record.respond_to?(:skip_email_validation) && user_record.skip_email_validation)
    next if respond_to?(:skip_validate_email) && skip_validate_email && !staged_check_enabled
    next if errors[:email].present?

    if user_record&.staged? && !SiteSetting.disify_email_protection_check_staged_users
      next
    end

    # Staged users are real persisted Discourse users. Classify them before
    # the generic persisted-user/email-change branch so the dedicated staged
    # setting and telemetry flow remain authoritative for both creation and
    # later staged-account validation.
    flow = if user_record&.staged?
      "staged_user"
    elsif user_record&.persisted?
      "email_change"
    else
      "signup"
    end

    if flow == "signup" && !SiteSetting.disify_email_protection_check_registration
      next
    end
    if flow == "email_change" && !SiteSetting.disify_email_protection_check_email_changes
      next
    end

    validation_fingerprint = "#{email.to_s.downcase}|#{flow}|#{SiteSetting.disify_email_protection_mode}"
    result =
      if defined?(@disify_email_protection_validation_fingerprint) &&
           @disify_email_protection_validation_fingerprint == validation_fingerprint &&
           defined?(@disify_email_protection_validation_result)
        @disify_email_protection_validation_result
      else
        @disify_email_protection_validation_fingerprint = validation_fingerprint
        @disify_email_protection_validation_result =
          ::DisifyEmailProtection::Decision.evaluate(
            email: email,
            user: user_record,
            flow: flow,
          )
      end

    case result.decision
    when "block"
      errors.add(:email, I18n.t("disify_email_protection.errors.#{result.user_message_key}"))
    when "review"
      errors.add(:email, I18n.t("disify_email_protection.errors.review_required"))
    end
  end

  # Privacy/lifecycle cleanup must run even when the protection setting is temporarily
  # disabled. Plugin#on intentionally suppresses handlers while a plugin is disabled,
  # so use the core event directly for this one lifecycle-only handler.
  DiscourseEvent.on(:user_anonymized) do |payload|
    user_record = payload.is_a?(Hash) ? (payload[:user] || payload["user"]) : payload
    next if user_record.blank?

    unless ::DisifyEmailProtection::PrivacyCleanup.anonymize_user!(user_record)
      begin
        Jobs.enqueue(:disify_email_protection_anonymize_cleanup, user_id: user_record.id)
      rescue StandardError => e
        Rails.logger.warn(
          "[disify_email_protection] anonymization cleanup retry enqueue failed class=#{e.class}",
        )
      end
    end
  end

  Discourse::Application.routes.append do
    get "/admin/plugins/disify-email-protection" => "admin/plugins#index",
        constraints: AdminConstraint.new
    get "/admin/plugins/disify-email-protection-health" => "admin/plugins#index",
        constraints: AdminConstraint.new
    get "/admin/plugins/disify-email-protection-statistics" => "admin/plugins#index",
        constraints: AdminConstraint.new
    get "/admin/plugins/disify-email-protection-review" => "admin/plugins#index",
        constraints: AdminConstraint.new
    get "/admin/plugins/disify-email-protection-tools" => "admin/plugins#index",
        constraints: AdminConstraint.new

    get "/admin/plugins/disify-email-protection/overview" =>
          "disify_email_protection/admin#overview",
        defaults: { format: :json },
        constraints: AdminConstraint.new
    get "/admin/plugins/disify-email-protection/health" =>
          "disify_email_protection/admin#health",
        defaults: { format: :json },
        constraints: AdminConstraint.new
    post "/admin/plugins/disify-email-protection/health/test" =>
           "disify_email_protection/admin#health_test",
         defaults: { format: :json },
         constraints: AdminConstraint.new
    post "/admin/plugins/disify-email-protection/health/reset-circuit" =>
           "disify_email_protection/admin#reset_circuit",
         defaults: { format: :json },
         constraints: AdminConstraint.new
    get "/admin/plugins/disify-email-protection/statistics" =>
          "disify_email_protection/admin#statistics",
        defaults: { format: :json },
        constraints: AdminConstraint.new
    get "/admin/plugins/disify-email-protection/review" =>
          "disify_email_protection/admin#review",
        defaults: { format: :json },
        constraints: AdminConstraint.new
    post "/admin/plugins/disify-email-protection/review/:id/approve" =>
           "disify_email_protection/admin#approve_review",
         defaults: { format: :json },
         constraints: AdminConstraint.new
    post "/admin/plugins/disify-email-protection/review/:id/approve-permanent" =>
           "disify_email_protection/admin#approve_review_permanently",
         defaults: { format: :json },
         constraints: AdminConstraint.new
    post "/admin/plugins/disify-email-protection/review/:id/reject" =>
           "disify_email_protection/admin#reject_review",
         defaults: { format: :json },
         constraints: AdminConstraint.new
    post "/admin/plugins/disify-email-protection/review/:id/recheck" =>
           "disify_email_protection/admin#recheck_review",
         defaults: { format: :json },
         constraints: AdminConstraint.new
    get "/admin/plugins/disify-email-protection/tools" =>
          "disify_email_protection/admin#tools",
        defaults: { format: :json },
        constraints: AdminConstraint.new
    post "/admin/plugins/disify-email-protection/tools/check" =>
           "disify_email_protection/admin#manual_check",
         defaults: { format: :json },
         constraints: AdminConstraint.new
    get "/admin/plugins/disify-email-protection/tools/scan/status" =>
          "disify_email_protection/admin#scan_status",
        defaults: { format: :json },
        constraints: AdminConstraint.new
    post "/admin/plugins/disify-email-protection/tools/scan" =>
           "disify_email_protection/admin#start_scan",
         defaults: { format: :json },
         constraints: AdminConstraint.new
    post "/admin/plugins/disify-email-protection/tools/scan/resume" =>
           "disify_email_protection/admin#resume_scan",
         defaults: { format: :json },
         constraints: AdminConstraint.new
    post "/admin/plugins/disify-email-protection/tools/scan/cancel" =>
           "disify_email_protection/admin#cancel_scan",
         defaults: { format: :json },
         constraints: AdminConstraint.new
    post "/admin/plugins/disify-email-protection/exceptions" =>
           "disify_email_protection/admin#create_exception",
         defaults: { format: :json },
         constraints: AdminConstraint.new
    delete "/admin/plugins/disify-email-protection/exceptions/:id" =>
             "disify_email_protection/admin#delete_exception",
           defaults: { format: :json },
           constraints: AdminConstraint.new
  end
end

# frozen_string_literal: true

module ::DisifyEmailProtection
  module StaffAudit
    module_function

    ALLOWED_ACTIONS = %w[
      review_approved
      review_approved_permanently
      review_rejected
      policy_exception_created
      policy_exception_deleted
      scan_started
      scan_resumed
      scan_cancelled
      circuit_reset
    ].freeze
    SAFE_DETAIL_KEYS = %i[
      review_id
      resolution
      exception_id
      exception_kind
      scan_id
      scan_mode
      scan_status
    ].freeze
    SAFE_TOKEN = /\A[a-z0-9_.:-]{1,80}\z/i

    def log!(actor:, action:, details: {})
      return false unless actor&.admin?

      action = action.to_s
      return false unless ALLOWED_ACTIONS.include?(action)

      safe_details = { subject: "DISIFY email protection" }
      details.to_h.slice(*SAFE_DETAIL_KEYS).each do |key, value|
        sanitized = sanitize_detail(value)
        safe_details[key] = sanitized unless sanitized.nil?
      end

      StaffActionLogger.new(actor).log_custom(
        "disify_email_protection_#{action}",
        safe_details,
      )
      true
    rescue StandardError => e
      # Audit logging must never make the protected admin action fail. Deliberately
      # log only the exception class; details may contain security-sensitive state.
      Rails.logger.warn("[disify_email_protection] staff audit failed class=#{e.class}")
      false
    end

    def sanitize_detail(value)
      return value if value.is_a?(Integer) && value >= 0

      token = value.to_s
      SAFE_TOKEN.match?(token) ? token : nil
    end
  end
end

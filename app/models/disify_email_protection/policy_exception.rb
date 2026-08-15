# frozen_string_literal: true

module ::DisifyEmailProtection
  class PolicyException < ::ActiveRecord::Base
    self.table_name = "disify_email_protection_policy_exceptions"

    belongs_to :created_by, class_name: "User", optional: true

    KINDS = %w[allow_domain block_domain allow_email_hmac block_email_hmac].freeze

    validates :kind, :value, presence: true
    validates :kind, inclusion: { in: KINDS }

    scope :effective, -> {
      where(active: true).where("expires_at IS NULL OR expires_at > ?", Time.zone.now)
    }
  end
end

# frozen_string_literal: true

module ::DisifyEmailProtection
  class EmailRemediation < ::ActiveRecord::Base
    self.table_name = "disify_email_protection_remediations"

    STATES = %w[required verification_pending resolved cancelled].freeze
    ACTIVE_STATES = %w[required verification_pending].freeze

    belongs_to :user
    belongs_to :review_item, class_name: "DisifyEmailProtection::ReviewItem", optional: true
    belongs_to :required_by, class_name: "User", optional: true

    validates :email_hmac, presence: true, format: { with: /\A[0-9a-f]{64}\z/ }
    validates :email_domain, length: { maximum: 255 }, allow_nil: true
    validates :reason, presence: true, length: { maximum: 32 }
    validates :state, inclusion: { in: STATES }, length: { maximum: 32 }
    validates :resolution, length: { maximum: 32 }, allow_nil: true
    validates :confidence,
              numericality: {
                only_integer: true,
                greater_than_or_equal_to: 0,
                less_than_or_equal_to: 100,
              },
              allow_nil: true
    validates :required_at, :enforce_at, presence: true

    scope :active, -> { where(active: true, state: ACTIVE_STATES) }
    scope :required, -> { active.where(state: "required") }
    scope :verification_pending, -> { active.where(state: "verification_pending") }
  end
end

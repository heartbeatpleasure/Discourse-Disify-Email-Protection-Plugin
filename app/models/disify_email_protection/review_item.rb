# frozen_string_literal: true

module ::DisifyEmailProtection
  class ReviewItem < ::ActiveRecord::Base
    self.table_name = "disify_email_protection_review_items"

    belongs_to :user, optional: true
    belongs_to :resolved_by, class_name: "User", optional: true

    STATES = %w[pending approved rejected expired].freeze

    validates :flow, :reason, :state, presence: true
    validates :state, inclusion: { in: STATES }, length: { maximum: 16 }
    validates :flow, :reason, length: { maximum: 32 }
    validates :email_domain, length: { maximum: 255 }, allow_nil: true
    validates :email_hmac, format: { with: /\A[0-9a-f]{64}\z/ }, allow_nil: true
    validates :confidence, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true

    scope :pending, -> { where(state: "pending") }
  end
end

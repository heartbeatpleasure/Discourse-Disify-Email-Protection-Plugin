# frozen_string_literal: true

module ::DisifyEmailProtection
  class ReviewItem < ::ActiveRecord::Base
    self.table_name = "disify_email_protection_review_items"

    belongs_to :user, optional: true
    belongs_to :resolved_by, class_name: "User", optional: true

    STATES = %w[pending approved rejected expired].freeze

    validates :flow, :reason, :state, presence: true
    validates :state, inclusion: { in: STATES }

    scope :pending, -> { where(state: "pending") }
  end
end

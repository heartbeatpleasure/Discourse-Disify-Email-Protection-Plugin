# frozen_string_literal: true

module ::DisifyEmailProtection
  class EmailEvent < ::ActiveRecord::Base
    self.table_name = "disify_email_protection_events"

    belongs_to :user, optional: true

    validates :flow, :mode, :decision, :reason, :disify_status, :source, :occurred_at, presence: true
    validates :flow, length: { maximum: 32 }
    validates :mode, :decision, :source, length: { maximum: 16 }
    validates :reason, length: { maximum: 32 }
    validates :disify_status, length: { maximum: 24 }
    validates :email_domain, length: { maximum: 255 }, allow_nil: true
    validates :email_hmac, format: { with: /\A[0-9a-f]{64}\z/ }, allow_nil: true
    validates :confidence, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
    validates :latency_ms, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  end
end

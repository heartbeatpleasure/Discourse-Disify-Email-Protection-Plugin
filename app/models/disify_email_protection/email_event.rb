# frozen_string_literal: true

module ::DisifyEmailProtection
  class EmailEvent < ::ActiveRecord::Base
    self.table_name = "disify_email_protection_events"

    belongs_to :user, optional: true

    validates :flow, :mode, :decision, :reason, :disify_status, :source, :occurred_at, presence: true
  end
end

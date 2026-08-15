# frozen_string_literal: true

module ::DisifyEmailProtection
  class EmailCheck < ::ActiveRecord::Base
    self.table_name = "disify_email_protection_checks"

    validates :cache_key, :check_type, :email_domain, :checked_at, :expires_at, presence: true
    validates :cache_key, uniqueness: true

    scope :fresh, -> { where("expires_at > ?", Time.zone.now) }
  end
end

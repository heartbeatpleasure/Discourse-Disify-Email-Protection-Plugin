# frozen_string_literal: true

module ::DisifyEmailProtection
  class DailyStat < ::ActiveRecord::Base
    self.table_name = "disify_email_protection_daily_stats"

    validates :stat_date, presence: true, uniqueness: true
  end
end

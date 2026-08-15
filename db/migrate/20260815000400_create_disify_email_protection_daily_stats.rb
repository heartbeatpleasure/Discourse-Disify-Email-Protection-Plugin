# frozen_string_literal: true

class CreateDisifyEmailProtectionDailyStats < ActiveRecord::Migration[7.0]
  def change
    create_table :disify_email_protection_daily_stats do |t|
      t.date :stat_date, null: false
      t.integer :checked, null: false, default: 0
      t.integer :allowed, null: false, default: 0
      t.integer :monitored, null: false, default: 0
      t.integer :reviewed, null: false, default: 0
      t.integer :blocked_disposable, null: false, default: 0
      t.integer :blocked_no_mx, null: false, default: 0
      t.integer :blocked_other, null: false, default: 0
      t.integer :fail_open, null: false, default: 0
      t.integer :api_calls, null: false, default: 0
      t.integer :cache_hits, null: false, default: 0
      t.integer :bypassed, null: false, default: 0
      t.integer :api_errors, null: false, default: 0
      t.bigint :latency_total_ms, null: false, default: 0
      t.integer :latency_samples, null: false, default: 0
      t.timestamps null: false
    end

    add_index :disify_email_protection_daily_stats, :stat_date,
              unique: true, name: "idx_disify_daily_stats_date"
  end
end

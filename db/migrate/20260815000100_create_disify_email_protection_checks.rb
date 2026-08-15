# frozen_string_literal: true

class CreateDisifyEmailProtectionChecks < ActiveRecord::Migration[7.0]
  def change
    create_table :disify_email_protection_checks do |t|
      t.string :cache_key, null: false, limit: 96
      t.string :check_type, null: false, limit: 16
      t.string :email_domain, null: false, limit: 255
      t.jsonb :result, null: false, default: {}
      t.datetime :checked_at, null: false
      t.datetime :expires_at, null: false
      t.timestamps null: false
    end

    add_index :disify_email_protection_checks, :cache_key,
              unique: true, name: "idx_disify_checks_cache_key"
    add_index :disify_email_protection_checks, :expires_at,
              name: "idx_disify_checks_expires_at"
  end
end

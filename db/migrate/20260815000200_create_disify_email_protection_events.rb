# frozen_string_literal: true

class CreateDisifyEmailProtectionEvents < ActiveRecord::Migration[7.0]
  def change
    create_table :disify_email_protection_events do |t|
      t.string :flow, null: false, limit: 32
      t.integer :user_id
      t.string :email_domain, limit: 255
      t.string :email_hmac, limit: 64
      t.string :mode, null: false, limit: 16
      t.string :decision, null: false, limit: 16
      t.string :reason, null: false, limit: 32
      t.integer :confidence
      t.jsonb :signals, null: false, default: []
      t.string :disify_status, null: false, limit: 24
      t.integer :latency_ms
      t.string :source, null: false, limit: 16
      t.datetime :occurred_at, null: false
    end

    add_index :disify_email_protection_events, :occurred_at,
              name: "idx_disify_events_occurred"
    add_index :disify_email_protection_events, %i[decision occurred_at],
              name: "idx_disify_events_decision_time"
    add_index :disify_email_protection_events, %i[user_id occurred_at],
              name: "idx_disify_events_user_time"
    add_foreign_key :disify_email_protection_events, :users,
                    column: :user_id, on_delete: :nullify
  end
end

# frozen_string_literal: true

class CreateDisifyEmailProtectionReviewItems < ActiveRecord::Migration[7.0]
  def change
    create_table :disify_email_protection_review_items do |t|
      t.integer :user_id
      t.string :email_domain, limit: 255
      t.string :email_hmac, limit: 64
      t.string :flow, null: false, limit: 32
      t.string :reason, null: false, limit: 32
      t.integer :confidence
      t.jsonb :signals, null: false, default: []
      t.string :state, null: false, default: "pending", limit: 16
      t.integer :resolved_by_id
      t.datetime :resolved_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps null: false
    end

    add_index :disify_email_protection_review_items, %i[state created_at],
              name: "idx_disify_review_state_time"
    add_index :disify_email_protection_review_items, %i[email_hmac state],
              name: "idx_disify_review_hmac_state"
    add_index :disify_email_protection_review_items, :user_id,
              name: "idx_disify_review_user"
    add_foreign_key :disify_email_protection_review_items, :users,
                    column: :user_id, on_delete: :nullify
    add_foreign_key :disify_email_protection_review_items, :users,
                    column: :resolved_by_id, on_delete: :nullify
  end
end

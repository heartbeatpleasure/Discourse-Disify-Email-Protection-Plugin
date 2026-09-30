# frozen_string_literal: true

class CreateDisifyEmailProtectionRemediations < ActiveRecord::Migration[7.0]
  def change
    create_table :disify_email_protection_remediations do |t|
      t.integer :user_id, null: false
      t.integer :review_item_id
      t.integer :required_by_id
      t.string :email_hmac, null: false, limit: 64
      t.string :email_domain, limit: 255
      t.string :reason, null: false, limit: 32
      t.integer :confidence
      t.string :state, null: false, default: "required", limit: 32
      t.boolean :active, null: false, default: true
      t.datetime :required_at, null: false
      t.datetime :enforce_at, null: false
      t.datetime :notified_at
      t.datetime :reminder_sent_at
      t.datetime :restricted_at
      t.datetime :resolved_at
      t.string :resolution, limit: 32
      t.timestamps null: false
    end

    add_index :disify_email_protection_remediations, :user_id,
              unique: true,
              where: "active = true",
              name: "idx_disify_remediation_active_user"
    add_index :disify_email_protection_remediations, %i[active state enforce_at],
              name: "idx_disify_remediation_state_due"
    add_index :disify_email_protection_remediations, :review_item_id,
              name: "idx_disify_remediation_review"
    add_foreign_key :disify_email_protection_remediations, :users,
                    column: :user_id, on_delete: :cascade
    add_foreign_key :disify_email_protection_remediations,
                    :disify_email_protection_review_items,
                    column: :review_item_id,
                    on_delete: :nullify
    add_foreign_key :disify_email_protection_remediations, :users,
                    column: :required_by_id, on_delete: :nullify
  end
end

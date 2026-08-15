# frozen_string_literal: true

class CreateDisifyEmailProtectionPolicyExceptions < ActiveRecord::Migration[7.0]
  def change
    create_table :disify_email_protection_policy_exceptions do |t|
      t.string :kind, null: false, limit: 32
      t.string :value, null: false, limit: 255
      t.string :reason, limit: 500
      t.integer :created_by_id
      t.datetime :expires_at
      t.boolean :active, null: false, default: true
      t.timestamps null: false
    end

    add_index :disify_email_protection_policy_exceptions, %i[kind value active],
              name: "idx_disify_policy_kind_value_active"
    add_foreign_key :disify_email_protection_policy_exceptions, :users,
                    column: :created_by_id, on_delete: :nullify
  end
end

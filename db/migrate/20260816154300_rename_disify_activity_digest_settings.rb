# frozen_string_literal: true

class RenameDisifyActivityDigestSettings < ActiveRecord::Migration[7.0]
  def up
    rename_setting(
      "disify_email_protection_moderator_digest_enabled",
      "disify_email_protection_activity_digest_enabled",
    )
    rename_setting(
      "disify_email_protection_moderator_digest_group",
      "disify_email_protection_activity_digest_recipients",
    )

    # The old setting accepted any group name. The new UI intentionally allows
    # only admins or staff. Preserve those two known values; fall back to admins
    # for any custom legacy group to avoid unexpectedly widening recipients.
    execute <<~SQL
      UPDATE site_settings
      SET value = CASE
        WHEN LOWER(value) = 'staff' THEN 'staff'
        WHEN LOWER(value) = 'admins' THEN 'admins'
        ELSE 'admins'
      END
      WHERE name = 'disify_email_protection_activity_digest_recipients'
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def rename_setting(old_name, new_name)
    old_name = connection.quote(old_name)
    new_name = connection.quote(new_name)

    execute <<~SQL
      DELETE FROM site_settings old_settings
      WHERE old_settings.name = #{old_name}
        AND EXISTS (
          SELECT 1
          FROM site_settings new_settings
          WHERE new_settings.name = #{new_name}
        )
    SQL

    execute <<~SQL
      UPDATE site_settings
      SET name = #{new_name}
      WHERE name = #{old_name}
    SQL
  end
end

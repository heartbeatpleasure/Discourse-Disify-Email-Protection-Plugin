# frozen_string_literal: true

class ScrubDisifyEmailProtectionTypoSuggestions < ActiveRecord::Migration[7.0]
  def up
    execute <<~SQL
      UPDATE disify_email_protection_checks
      SET result = result - 'typo_suggestion',
          updated_at = CURRENT_TIMESTAMP
      WHERE check_type = 'email'
        AND result ? 'typo_suggestion'
    SQL
  end

  def down
    # Intentionally irreversible from a data perspective: removed email-address
    # suggestions are privacy-sensitive and must never be reconstructed.
  end
end

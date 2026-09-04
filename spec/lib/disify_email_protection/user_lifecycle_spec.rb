# frozen_string_literal: true

require "rails_helper"

RSpec.describe DisifyEmailProtection::UserLifecycle do
  fab!(:user)

  it "yields an active user while holding a database row lock" do
    expect(User).to receive(:lock).and_call_original

    yielded = described_class.with_active_user_id(user.id) { |locked_user| locked_user.id }

    expect(yielded).to eq(user.id)
  end

  it "does not yield once the account has been anonymized" do
    user.primary_email.update_columns(
      email: "anon#{user.id}@anonymized.invalid",
      normalized_email: "anon#{user.id}@anonymized.invalid",
    )
    yielded = false

    result = described_class.with_active_user_id(user.id) do |_locked_user|
      yielded = true
    end

    expect(result).to be_nil
    expect(yielded).to eq(false)
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Jobs::DisifyEmailProtectionRecordValidationResult do
  fab!(:user)

  let(:email) { "blocked-candidate@example.com" }
  let(:base_args) do
    {
      email_hmac: DisifyEmailProtection::Normalizer.email_hmac(email),
      email_domain: "example.com",
      user_id: user.id,
      flow: "email_change",
      mode: "enforce",
      decision: "block",
      reason: "disposable",
      confidence: 100,
      signals: ["blacklist_exact"],
      status: "success",
      latency_ms: 25,
      source: "api",
      counters: { checked: 1, blocked_disposable: 1, api_calls: 1 },
    }
  end

  it "persists aggregate statistics and a fingerprint event outside the validation transaction" do
    SiteSetting.disify_email_protection_user_notes_enabled = false

    expect do
      described_class.new.execute(base_args)
    end.to change { DisifyEmailProtection::EmailEvent.count }.by(1)

    event = DisifyEmailProtection::EmailEvent.order(:id).last
    expect(event.user_id).to eq(user.id)
    expect(event.email_hmac).to eq(DisifyEmailProtection::Normalizer.email_hmac(email))
    expect(event.email_domain).to eq("example.com")
    expect(event.decision).to eq("block")
  end

  it "does not recreate identifying event data for an anonymized user" do
    user.primary_email.update_columns(
      email: "anon#{user.id}@anonymized.invalid",
      normalized_email: "anon#{user.id}@anonymized.invalid",
    )

    expect do
      described_class.new.execute(base_args)
    end.not_to change { DisifyEmailProtection::EmailEvent.count }
  end
end

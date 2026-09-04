# frozen_string_literal: true

require "rails_helper"

RSpec.describe Jobs::DisifyEmailProtectionCreateReview do
  fab!(:user)

  it "materializes a queued fingerprint into a pending review item" do
    email = "candidate@example.com"
    expect do
      described_class.new.execute(
        email_hmac: DisifyEmailProtection::Normalizer.email_hmac(email),
        email_domain: "example.com",
        user_id: user.id,
        flow: "email_change",
        reason: "disposable",
        confidence: 100,
        signals: ["blacklist_exact"],
        metadata: { "source" => "api" },
      )
    end.to change { DisifyEmailProtection::ReviewItem.pending.count }.by(1)
  end

  it "does not recreate an old fingerprint for an anonymized user" do
    user.primary_email.update_columns(
      email: "anon#{user.id}@anonymized.invalid",
      normalized_email: "anon#{user.id}@anonymized.invalid",
    )

    expect do
      described_class.new.execute(
        email_hmac: "a" * 64,
        email_domain: "example.com",
        user_id: user.id,
        flow: "email_change",
        reason: "disposable",
        confidence: 100,
        signals: [],
        metadata: {},
      )
    end.not_to change { DisifyEmailProtection::ReviewItem.count }
  end
end

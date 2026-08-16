# frozen_string_literal: true

require "rails_helper"

RSpec.describe DisifyEmailProtection::ModeratorDigest do
  fab!(:admin)

  before do
    SiteSetting.disify_email_protection_enabled = true
    SiteSetting.disify_email_protection_moderator_digest_enabled = true
    SiteSetting.disify_email_protection_moderator_digest_group = "staff"
  end

  it "does not send the daily activity digest solely because an old item remains pending" do
    DisifyEmailProtection::ReviewItem.create!(
      user_id: admin.id,
      email_domain: "example.com",
      email_hmac: "b" * 64,
      flow: "existing_user_scan",
      reason: "disposable",
      confidence: 100,
      signals: [],
      state: "pending",
      metadata: {},
      created_at: 2.days.ago,
      updated_at: 2.days.ago,
    )

    expect(PostCreator).not_to receive(:create!)

    expect(described_class.send_if_needed!).to eq(false)
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe DisifyEmailProtection::StaffAudit do
  fab!(:admin)
  fab!(:user)

  it "records only allowlisted metadata for administrators" do
    logger = instance_double(StaffActionLogger)
    allow(StaffActionLogger).to receive(:new).with(admin).and_return(logger)
    expect(logger).to receive(:log_custom) do |action, details|
      expect(action).to eq("disify_email_protection_review_approved")
      expect(details[:review_id]).to eq(42)
      expect(details[:resolution]).to eq("allow_7_days")
      expect(details).not_to have_key(:email)
      expect(details).not_to have_key(:api_key)
    end

    expect(
      described_class.log!(
        actor: admin,
        action: "review_approved",
        details: { review_id: 42, resolution: "allow_7_days", email: "secret@example.com" },
      ),
    ).to eq(true)
  end

  it "does not create staff audit entries for non-admin users" do
    expect(StaffActionLogger).not_to receive(:new)
    expect(described_class.log!(actor: user, action: "review_approved", details: {})).to eq(false)
  end
end

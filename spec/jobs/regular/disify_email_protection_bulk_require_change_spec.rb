# frozen_string_literal: true

require "rails_helper"

RSpec.describe Jobs::DisifyEmailProtectionBulkRequireChange do
  fab!(:admin)
  fab!(:user)
  fab!(:other_user) { Fabricate(:user) }

  before do
    SiteSetting.disify_email_protection_existing_user_remediation_enabled = true
    SiteSetting.disify_email_protection_bulk_remediation_enabled = true
    SiteSetting.disify_email_protection_remediation_user_pm_enabled = false
  end

  def review_for(target_user)
    DisifyEmailProtection::ReviewItem.create!(
      user_id: target_user.id,
      email_domain: DisifyEmailProtection::Normalizer.domain(target_user.email),
      email_hmac: DisifyEmailProtection::Normalizer.email_hmac(target_user.email),
      flow: "existing_user_scan",
      reason: "disposable",
      confidence: 100,
      signals: [],
      state: "pending",
      metadata: {},
    )
  end

  it "processes only the review ids snapshotted by the administrator" do
    selected = review_for(user)
    later = review_for(other_user)
    allow(DisifyEmailProtection::UserNoteWriter).to receive(:record!)

    described_class.new.execute(
      actor_id: admin.id,
      state: "pending",
      review_ids: [selected.id],
    )

    expect(selected.reload.state).to eq("remediation")
    expect(later.reload.state).to eq("pending")
    expect(DisifyEmailProtection::EmailRemediation.where(user_id: user.id, active: true)).to exist
    expect(DisifyEmailProtection::EmailRemediation.where(user_id: other_user.id, active: true)).not_to exist
  end
end

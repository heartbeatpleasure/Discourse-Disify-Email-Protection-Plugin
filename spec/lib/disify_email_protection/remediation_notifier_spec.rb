# frozen_string_literal: true

require "rails_helper"

RSpec.describe DisifyEmailProtection::RemediationNotifier do
  fab!(:admin)
  fab!(:user)

  before do
    SiteSetting.disify_email_protection_remediation_user_pm_enabled = true
  end

  def remediation(enforce_at:)
    DisifyEmailProtection::EmailRemediation.create!(
      user_id: user.id,
      required_by_id: admin.id,
      email_hmac: DisifyEmailProtection::Normalizer.email_hmac(user.email),
      email_domain: DisifyEmailProtection::Normalizer.domain(user.email),
      reason: "disposable",
      confidence: 100,
      state: "required",
      active: true,
      required_at: Time.zone.now,
      enforce_at: enforce_at,
      notified_at: 1.day.ago,
    )
  end

  it "sends at most a pre-deadline reminder and never a stale reminder after the deadline" do
    item = remediation(enforce_at: 6.days.from_now)
    expect(described_class.reminder_due?(item)).to eq(true)

    item.update!(enforce_at: 1.minute.ago)
    expect(described_class.reminder_due?(item.reload)).to eq(false)
  end
end

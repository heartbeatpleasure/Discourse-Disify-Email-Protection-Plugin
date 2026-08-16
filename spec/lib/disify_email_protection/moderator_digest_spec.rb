# frozen_string_literal: true

require "rails_helper"

RSpec.describe DisifyEmailProtection::ModeratorDigest do
  fab!(:admin)

  before do
    SiteSetting.disify_email_protection_enabled = true
    SiteSetting.disify_email_protection_activity_digest_enabled = true
    SiteSetting.disify_email_protection_activity_digest_recipients = "admins"
    SiteSetting.disify_email_protection_activity_digest_frequency = "weekly"
    SiteSetting.disify_email_protection_activity_digest_send_time = "09:00"
    SiteSetting.disify_email_protection_activity_digest_weekday = "monday"
    SiteSetting.disify_email_protection_activity_digest_day_of_month = 1
    PluginStore.remove(DisifyEmailProtection::STORE_NAMESPACE, described_class::LAST_PERIOD_END_KEY)
    PluginStore.remove(DisifyEmailProtection::STORE_NAMESPACE, described_class::LAST_SENT_KEY)
    PluginStore.remove(DisifyEmailProtection::STORE_NAMESPACE, described_class::LEGACY_LAST_SENT_KEY)
  end

  it "does not send an activity digest solely because an old item remains pending" do
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
      created_at: Time.utc(2026, 8, 1, 12, 0),
      updated_at: Time.utc(2026, 8, 1, 12, 0),
    )

    expect(PostCreator).not_to receive(:create!)

    expect(described_class.send_if_needed!(now: Time.utc(2026, 8, 17, 10, 0))).to eq(false)
  end

  it "initializes without backfilling historical activity when first enabled" do
    expect(PostCreator).not_to receive(:create!)

    expect(described_class.send_if_needed!(now: Time.utc(2026, 8, 19, 10, 0))).to eq(false)
    stored = PluginStore.get(DisifyEmailProtection::STORE_NAMESPACE, described_class::LAST_PERIOD_END_KEY)
    expect(Time.zone.parse(stored)).to eq(Time.utc(2026, 8, 17, 9, 0))
  end

  it "sends one grouped digest for new review activity and does not repeat the same period" do
    DisifyEmailProtection::ReviewItem.create!(
      user_id: admin.id,
      email_domain: "example.com",
      email_hmac: "c" * 64,
      flow: "existing_user_scan",
      reason: "disposable",
      confidence: 100,
      signals: [],
      state: "pending",
      metadata: {},
      created_at: Time.utc(2026, 8, 16, 12, 0),
      updated_at: Time.utc(2026, 8, 16, 12, 0),
    )

    PluginStore.set(
      DisifyEmailProtection::STORE_NAMESPACE,
      described_class::LAST_PERIOD_END_KEY,
      Time.utc(2026, 8, 10, 9, 0).iso8601,
    )

    expect(PostCreator).to receive(:create!).once.and_return(true)

    now = Time.utc(2026, 8, 17, 10, 0)
    expect(described_class.send_if_needed!(now: now)).to eq(true)
    expect(described_class.send_if_needed!(now: now + 30.minutes)).to eq(false)
  end

  it "uses the configured recipient scope" do
    SiteSetting.disify_email_protection_activity_digest_recipients = "staff"

    expect(described_class.recipient_group).to eq(Group[:staff])
  end

  it "calculates the most recent daily scheduled boundary in UTC" do
    SiteSetting.disify_email_protection_activity_digest_frequency = "daily"
    SiteSetting.disify_email_protection_activity_digest_send_time = "09:30"

    expect(described_class.scheduled_period_end(Time.utc(2026, 8, 16, 9, 15))).to eq(
      Time.utc(2026, 8, 15, 9, 30),
    )
    expect(described_class.scheduled_period_end(Time.utc(2026, 8, 16, 9, 45))).to eq(
      Time.utc(2026, 8, 16, 9, 30),
    )
  end

  it "uses the legacy digest timestamp to avoid an immediate duplicate after upgrade" do
    PluginStore.set(
      DisifyEmailProtection::STORE_NAMESPACE,
      described_class::LEGACY_LAST_SENT_KEY,
      Time.utc(2026, 8, 19, 9, 0).iso8601,
    )

    expect(described_class.send_if_needed!(now: Time.utc(2026, 8, 19, 10, 0))).to eq(false)
  end

  it "calculates weekly and monthly schedule boundaries" do
    SiteSetting.disify_email_protection_activity_digest_frequency = "weekly"
    SiteSetting.disify_email_protection_activity_digest_weekday = "monday"
    expect(described_class.scheduled_period_end(Time.utc(2026, 8, 19, 12, 0))).to eq(
      Time.utc(2026, 8, 17, 9, 0),
    )

    SiteSetting.disify_email_protection_activity_digest_frequency = "monthly"
    SiteSetting.disify_email_protection_activity_digest_day_of_month = 5
    expect(described_class.scheduled_period_end(Time.utc(2026, 8, 4, 12, 0))).to eq(
      Time.utc(2026, 7, 5, 9, 0),
    )
    expect(described_class.scheduled_period_end(Time.utc(2026, 8, 6, 12, 0))).to eq(
      Time.utc(2026, 8, 5, 9, 0),
    )
  end
end

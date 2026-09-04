# frozen_string_literal: true

require "rails_helper"

RSpec.describe DisifyEmailProtection::PrivacyCleanup do
  fab!(:user)
  fab!(:admin)

  it "scrubs user-linked email protection data when Discourse anonymizes a user" do
    email = user.email
    hmac = DisifyEmailProtection::Normalizer.email_hmac(email)
    domain = DisifyEmailProtection::Normalizer.domain(email)

    event = DisifyEmailProtection::EmailEvent.create!(
      flow: "email_change",
      user_id: user.id,
      email_domain: domain,
      email_hmac: hmac,
      mode: "review",
      decision: "review",
      reason: "disposable",
      confidence: 100,
      signals: ["blacklist_exact"],
      disify_status: "success",
      source: "api",
      occurred_at: Time.zone.now,
    )
    DisifyEmailProtection::ReviewItem.create!(
      user_id: user.id,
      email_domain: domain,
      email_hmac: hmac,
      flow: "email_change",
      reason: "disposable",
      confidence: 100,
      signals: ["blacklist_exact"],
      state: "pending",
      metadata: {},
    )
    DisifyEmailProtection::PolicyException.create!(
      kind: "allow_email_hmac",
      value: hmac,
      created_by_id: admin.id,
      active: true,
    )
    DisifyEmailProtection::EmailCheck.create!(
      cache_key: "email:#{hmac}",
      check_type: "email",
      email_domain: domain,
      result: { "format" => true },
      checked_at: Time.zone.now,
      expires_at: 15.minutes.from_now,
    )

    expect(described_class.anonymize_user!(user)).to eq(true)

    event.reload
    expect(event.user_id).to be_nil
    expect(event.email_domain).to be_nil
    expect(event.email_hmac).to be_nil
    expect(DisifyEmailProtection::ReviewItem.where(user_id: user.id)).to be_empty
    expect(DisifyEmailProtection::PolicyException.where(value: hmac).exists?).to eq(true)
    expect(DisifyEmailProtection::EmailCheck.where(cache_key: "email:#{hmac}")).to be_empty
  end

  it "is wired to Discourse's user_anonymized event" do
    event = DisifyEmailProtection::EmailEvent.create!(
      flow: "signup",
      user_id: user.id,
      email_domain: "example.com",
      email_hmac: DisifyEmailProtection::Normalizer.email_hmac(user.email),
      mode: "monitor",
      decision: "allow",
      reason: "clean",
      signals: [],
      disify_status: "success",
      source: "api",
      occurred_at: Time.zone.now,
    )

    DiscourseEvent.trigger(:user_anonymized, user: user, opts: {})

    expect(event.reload.user_id).to be_nil
    expect(event.email_hmac).to be_nil
  end

  it "runs anonymization cleanup even while the protection setting is disabled" do
    SiteSetting.disify_email_protection_enabled = false
    event = DisifyEmailProtection::EmailEvent.create!(
      flow: "signup",
      user_id: user.id,
      email_domain: "example.com",
      email_hmac: DisifyEmailProtection::Normalizer.email_hmac(user.email),
      mode: "monitor",
      decision: "allow",
      reason: "clean",
      signals: [],
      disify_status: "success",
      source: "api",
      occurred_at: Time.zone.now,
    )

    DiscourseEvent.trigger(:user_anonymized, user: user, opts: {})

    expect(event.reload.user_id).to be_nil
    expect(event.email_hmac).to be_nil
  end

  it "queues a retry when immediate cleanup after the core anonymization event fails" do
    allow(described_class).to receive(:anonymize_user!).with(user).and_return(false)
    expect(Jobs).to receive(:enqueue).with(
      :disify_email_protection_anonymize_cleanup,
      user_id: user.id,
    )

    DiscourseEvent.trigger(:user_anonymized, user: user, opts: {})
  end

  it "makes the retry job fail explicitly when cleanup is still unavailable" do
    allow(described_class).to receive(:anonymize_user!).with(user).and_return(false)

    expect do
      Jobs::DisifyEmailProtectionAnonymizeCleanup.new.execute(user_id: user.id)
    end.to raise_error(RuntimeError, /anonymization cleanup failed/)
  end

end

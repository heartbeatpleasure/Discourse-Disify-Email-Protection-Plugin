# frozen_string_literal: true

require "rails_helper"

RSpec.describe Jobs::DisifyEmailProtectionCleanup do
  it "removes cache rows as soon as they are expired and prunes note debounce state" do
    expired = DisifyEmailProtection::EmailCheck.create!(
      cache_key: "domain:expired.example",
      check_type: "domain",
      email_domain: "expired.example",
      result: {},
      checked_at: 2.hours.ago,
      expires_at: 1.minute.ago,
    )
    fresh = DisifyEmailProtection::EmailCheck.create!(
      cache_key: "domain:fresh.example",
      check_type: "domain",
      email_domain: "fresh.example",
      result: {},
      checked_at: Time.zone.now,
      expires_at: 1.hour.from_now,
    )
    expect(DisifyEmailProtection::UserNoteWriter).to receive(:cleanup_stale_debounce!).with(
      now: kind_of(ActiveSupport::TimeWithZone),
    )

    described_class.new.execute({})

    expect(DisifyEmailProtection::EmailCheck.exists?(expired.id)).to eq(false)
    expect(DisifyEmailProtection::EmailCheck.exists?(fresh.id)).to eq(true)
  end
end

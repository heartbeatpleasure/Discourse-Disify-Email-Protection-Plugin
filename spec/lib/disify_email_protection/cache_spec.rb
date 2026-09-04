# frozen_string_literal: true

require "rails_helper"

RSpec.describe DisifyEmailProtection::Cache do
  before do
    SiteSetting.disify_email_protection_email_hmac_cache_ttl_minutes = 15
    SiteSetting.disify_email_protection_domain_cache_ttl_hours = 24
  end

  it "never persists a raw typo-suggestion email in an exact-email cache row" do
    email = "member@example.com"
    suggestion = "member@example.org"
    result = {
      "format" => true,
      "domain" => "example.com",
      "disposable" => false,
      "dns" => true,
      "role" => false,
      "confidence" => 100,
      "signals" => [],
      "typo_suggestion" => suggestion,
    }

    described_class.write_email(email, result)

    row =
      DisifyEmailProtection::EmailCheck.find_by!(
        cache_key: "email:#{DisifyEmailProtection::Normalizer.email_hmac(email)}",
      )
    expect(row.result).not_to have_key("typo_suggestion")
    expect(row.result.to_json).not_to include(suggestion)
  end

  it "strips legacy typo suggestions when an existing cache row is read" do
    email = "member@example.com"
    hmac = DisifyEmailProtection::Normalizer.email_hmac(email)
    DisifyEmailProtection::EmailCheck.create!(
      cache_key: "email:#{hmac}",
      check_type: "email",
      email_domain: "example.com",
      result: {
        "format" => true,
        "domain" => "example.com",
        "disposable" => false,
        "dns" => true,
        "confidence" => 100,
        "typo_suggestion" => "legacy@example.org",
      },
      checked_at: Time.zone.now,
      expires_at: 15.minutes.from_now,
    )

    expect(described_class.fetch_email(email).dig("result", "typo_suggestion")).to be_nil
  end
end

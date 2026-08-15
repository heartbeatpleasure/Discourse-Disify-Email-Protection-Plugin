# frozen_string_literal: true

require "rails_helper"

RSpec.describe DisifyEmailProtection::Normalizer do
  describe ".email" do
    it "normalizes surrounding whitespace and case" do
      expect(described_class.email("  Member@Example.COM  ")).to eq("member@example.com")
    end
  end

  describe ".domain" do
    it "extracts the normalized domain" do
      expect(described_class.domain("Member@Example.COM")).to eq("example.com")
    end

    it "returns nil for unusable input" do
      expect(described_class.domain("not-an-email")).to be_nil
    end
  end

  describe ".email_hmac" do
    it "is deterministic without containing the source email" do
      first = described_class.email_hmac("member@example.com")
      second = described_class.email_hmac("MEMBER@example.com")

      expect(first).to eq(second)
      expect(first).to match(/\A[0-9a-f]{64}\z/)
      expect(first).not_to include("member")
      expect(first).not_to include("example")
    end
  end
end

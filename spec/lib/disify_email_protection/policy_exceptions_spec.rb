# frozen_string_literal: true

require "rails_helper"

RSpec.describe DisifyEmailProtection::PolicyExceptions do
  describe ".valid_domain?" do
    it "accepts normal domains" do
      expect(described_class.valid_domain?("example.com")).to eq(true)
      expect(described_class.valid_domain?("mail.example.co.uk")).to eq(true)
    end

    it "rejects values that are not domains" do
      expect(described_class.valid_domain?("member@example.com")).to eq(false)
      expect(described_class.valid_domain?("https://example.com")).to eq(false)
      expect(described_class.valid_domain?("invalid domain")).to eq(false)
    end
  end

  describe "admin-only mutation hardening" do
    fab!(:admin)
    fab!(:user)

    it "rejects policy mutations from non-admin actors" do
      expect do
        described_class.create!(kind: "allow_domain", value: "example.com", actor: user)
      end.to raise_error(Discourse::InvalidAccess)
    end

    it "rejects unknown email exception actions" do
      expect do
        described_class.create_for_email!(
          action: "unexpected",
          email: "member@example.com",
          actor: admin,
        )
      end.to raise_error(Discourse::InvalidParameters)
    end
  end

end

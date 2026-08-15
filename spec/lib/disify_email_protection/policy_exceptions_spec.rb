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
end

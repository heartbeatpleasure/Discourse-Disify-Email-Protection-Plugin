# frozen_string_literal: true

require "rails_helper"

RSpec.describe DisifyEmailProtection::Decision do
  before do
    SiteSetting.disify_email_protection_block_disposable = true
    SiteSetting.disify_email_protection_disposable_confidence_threshold = 90
    SiteSetting.disify_email_protection_block_no_mx = true
    SiteSetting.disify_email_protection_role_email_action = "monitor"
  end

  describe ".policy_for" do
    it "blocks high-confidence disposable results" do
      action, reason, key = described_class.policy_for(
        "format" => true,
        "dns" => true,
        "disposable" => true,
        "confidence" => 100,
      )

      expect([action, reason, key]).to eq(%w[block disposable disposable_email])
    end

    it "monitors low-confidence disposable results" do
      action, reason, key = described_class.policy_for(
        "format" => true,
        "dns" => true,
        "disposable" => true,
        "confidence" => 70,
      )

      expect(action).to eq("monitor")
      expect(reason).to eq("disposable_low_confidence")
      expect(key).to be_nil
    end

    it "blocks a domain without mail exchange records" do
      action, reason, key = described_class.policy_for(
        "format" => true,
        "dns" => false,
        "disposable" => false,
        "confidence" => 0,
      )

      expect([action, reason, key]).to eq(%w[block no_mx no_mx])
    end

    it "allows normal free mailbox providers" do
      action, reason, = described_class.policy_for(
        "format" => true,
        "dns" => true,
        "disposable" => false,
        "free" => true,
        "role" => false,
      )

      expect(action).to eq("allow")
      expect(reason).to eq("clean")
    end
  end

  describe ".apply_mode" do
    it "turns an actionable block into monitoring in monitor mode" do
      expect(described_class.apply_mode("block", "monitor")).to eq("monitor")
    end

    it "turns an actionable block into review in review mode" do
      expect(described_class.apply_mode("block", "review")).to eq("review")
    end

    it "keeps an actionable block in enforce mode" do
      expect(described_class.apply_mode("block", "enforce")).to eq("block")
    end
  end

  describe ".evaluate during provider backoff" do
    it "still applies a cached risky-domain result while the circuit is open" do
      SiteSetting.disify_email_protection_enabled = true
      SiteSetting.disify_email_protection_mode = "enforce"
      cached = {
        "result" => {
          "format" => true,
          "dns" => true,
          "disposable" => true,
          "confidence" => 100,
          "signals" => ["blacklist_exact"],
        },
      }
      allow(DisifyEmailProtection::Cache).to receive(:fetch_email).and_return(nil)
      allow(DisifyEmailProtection::Cache).to receive(:fetch_risky_domain).and_return(cached)
      allow(DisifyEmailProtection::CircuitBreaker).to receive(:allow_request?).and_return(false)
      expect(DisifyEmailProtection::Client).not_to receive(:new)

      result = described_class.evaluate(
        email: "member@example.com",
        dry_run: true,
      )

      expect(result.decision).to eq("block")
      expect(result.reason).to eq("disposable")
      expect(result.source).to eq("cache")
    end
  end

  describe ".evaluate statistics for admin dry runs" do
    it "records aggregate statistics without creating normal event side effects" do
      SiteSetting.disify_email_protection_enabled = true
      SiteSetting.disify_email_protection_mode = "monitor"

      cached = {
        "result" => {
          "format" => true,
          "dns" => true,
          "disposable" => false,
          "confidence" => 0,
          "signals" => [],
        },
      }
      allow(DisifyEmailProtection::PolicyExceptions).to receive(:decision_for).and_return(nil)
      allow(DisifyEmailProtection::Cache).to receive(:fetch_email).and_return(cached)
      allow(DisifyEmailProtection::Cache).to receive(:fetch_risky_domain).and_return(nil)
      expect(DisifyEmailProtection::EventRecorder).not_to receive(:record!)
      expect(DisifyEmailProtection::ReviewQueue).not_to receive(:create_or_refresh!)
      expect(DisifyEmailProtection::Statistics).to receive(:increment!).with(
        hash_including(checked: 1, allowed: 1, cache_hits: 1),
      )

      result = described_class.evaluate(
        email: "member@example.com",
        flow: "admin_tool",
        dry_run: true,
      )

      expect(result.decision).to eq("allow")
      expect(result.source).to eq("cache")
    end
  end

end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe DisifyEmailProtection::AdminController do
  fab!(:admin)
  fab!(:user)

  describe "GET /admin/plugins/disify-email-protection/health.json" do
    it "requires an administrator" do
      sign_in(user)
      get "/admin/plugins/disify-email-protection/health.json"
      expect(response.status).to eq(404).or eq(403)
    end

    it "returns privacy-safe health data to administrators" do
      sign_in(admin)
      get "/admin/plugins/disify-email-protection/health.json"

      expect(response.status).to eq(200)
      json = response.parsed_body
      expect(json.dig("privacy", "raw_email_stored_in_plugin_tables")).to eq(false)
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(json.to_json).not_to include(SiteSetting.disify_email_protection_api_key.to_s) if SiteSetting.disify_email_protection_api_key.present?
    end
  end
  describe "GET /admin/plugins/disify-email-protection/tools/scan/status.json" do
    after do
      PluginStore.remove(DisifyEmailProtection::STORE_NAMESPACE, DisifyEmailProtection::ExistingUserScan::STATE_KEY)
    end

    it "requires an administrator" do
      sign_in(user)
      get "/admin/plugins/disify-email-protection/tools/scan/status.json"
      expect(response.status).to eq(404).or eq(403)
    end

    it "returns only the live scan state and quota to administrators" do
      PluginStore.set(
        DisifyEmailProtection::STORE_NAMESPACE,
        DisifyEmailProtection::ExistingUserScan::STATE_KEY,
        {
          "scan_id" => "status-spec-scan",
          "status" => "running",
          "started_at" => 1.minute.ago.iso8601,
          "last_activity_at" => Time.zone.now.iso8601,
          "processed" => 2,
          "flagged" => 1,
          "total" => 5,
        },
      )

      sign_in(admin)
      get "/admin/plugins/disify-email-protection/tools/scan/status.json"

      expect(response.status).to eq(200)
      json = response.parsed_body
      expect(json.dig("scan", "status")).to eq("running")
      expect(json.dig("scan", "processed")).to eq(2)
      expect(json).to have_key("quota")
      expect(json).not_to have_key("exceptions")
      expect(json).not_to have_key("scan_estimate")
      expect(response.headers["Cache-Control"]).to include("no-store")
    end
  end

  describe "POST /admin/plugins/disify-email-protection/tools/scan/cancel.json" do
    after do
      PluginStore.remove(DisifyEmailProtection::STORE_NAMESPACE, DisifyEmailProtection::ExistingUserScan::STATE_KEY)
    end

    it "requires an administrator" do
      sign_in(user)
      post "/admin/plugins/disify-email-protection/tools/scan/cancel.json"
      expect(response.status).to eq(404).or eq(403)
    end

    it "cancels an active scan for administrators" do
      PluginStore.set(
        DisifyEmailProtection::STORE_NAMESPACE,
        DisifyEmailProtection::ExistingUserScan::STATE_KEY,
        {
          "scan_id" => "request-spec-scan",
          "status" => "running",
          "started_at" => 1.minute.ago.iso8601,
          "last_activity_at" => Time.zone.now.iso8601,
        },
      )

      sign_in(admin)
      post "/admin/plugins/disify-email-protection/tools/scan/cancel.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body.dig("scan", "status")).to eq("cancelled")
    end
  end

  describe "POST /admin/plugins/disify-email-protection/tools/scan.json" do
    after do
      PluginStore.remove(DisifyEmailProtection::STORE_NAMESPACE, DisifyEmailProtection::ExistingUserScan::STATE_KEY)
    end

    it "treats a repeated start request id as the same scan" do
      allow(Jobs).to receive(:enqueue)
      sign_in(admin)

      params = { scan_mode: "domain_only", request_id: "request-spec-idempotency" }
      post "/admin/plugins/disify-email-protection/tools/scan.json", params: params
      expect(response.status).to eq(200)
      first_scan_id = response.parsed_body.dig("scan", "scan_id")

      post "/admin/plugins/disify-email-protection/tools/scan.json", params: params
      expect(response.status).to eq(200)
      expect(response.parsed_body.dig("scan", "scan_id")).to eq(first_scan_id)
      expect(Jobs).to have_received(:enqueue).once
    end
  end

end

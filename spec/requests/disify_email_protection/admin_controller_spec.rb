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
end

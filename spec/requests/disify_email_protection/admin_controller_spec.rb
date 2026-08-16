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

    it "returns only the live scan state to administrators" do
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
      expect(json).not_to have_key("quota")
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

  describe "POST /admin/plugins/disify-email-protection/review/:id/approve-permanent.json" do
    it "requires an administrator" do
      item = DisifyEmailProtection::ReviewItem.create!(
        user_id: user.id,
        email_domain: "example.com",
        email_hmac: DisifyEmailProtection::Normalizer.email_hmac("restricted-review@example.com"),
        flow: "existing_user_scan",
        reason: "disposable",
        confidence: 100,
        signals: ["blacklist_exact"],
        state: "pending",
        metadata: {},
      )

      sign_in(user)
      post "/admin/plugins/disify-email-protection/review/#{item.id}/approve-permanent.json"

      expect(response.status).to eq(404).or eq(403)
      expect(item.reload.state).to eq("pending")
    end

    it "permanently approves only the reviewed email HMAC for administrators" do
      email = "permanent-review@example.com"
      item = DisifyEmailProtection::ReviewItem.create!(
        user_id: user.id,
        email_domain: "example.com",
        email_hmac: DisifyEmailProtection::Normalizer.email_hmac(email),
        flow: "existing_user_scan",
        reason: "disposable",
        confidence: 100,
        signals: ["blacklist_exact"],
        state: "pending",
        metadata: {},
      )

      sign_in(admin)
      post "/admin/plugins/disify-email-protection/review/#{item.id}/approve-permanent.json"

      expect(response.status).to eq(200)
      exception = DisifyEmailProtection::PolicyException.order(:id).last
      expect(exception.kind).to eq("allow_email_hmac")
      expect(exception.value).to eq(item.email_hmac)
      expect(exception.expires_at).to be_nil
      expect(item.reload.metadata["resolution"]).to eq("allow_permanent")
    end
  end


  describe "admin route access-control matrix" do
    it "denies a normal user across all plugin JSON admin endpoints" do
      sign_in(user)
      requests = [
        [:get, "/admin/plugins/disify-email-protection/overview.json", {}],
        [:get, "/admin/plugins/disify-email-protection/health.json", {}],
        [:post, "/admin/plugins/disify-email-protection/health/test.json", {}],
        [:post, "/admin/plugins/disify-email-protection/health/reset-circuit.json", {}],
        [:get, "/admin/plugins/disify-email-protection/statistics.json", { period: 7 }],
        [:get, "/admin/plugins/disify-email-protection/review.json", { state: "pending", page: 1 }],
        [:post, "/admin/plugins/disify-email-protection/review/1/approve.json", {}],
        [:post, "/admin/plugins/disify-email-protection/review/1/approve-permanent.json", {}],
        [:post, "/admin/plugins/disify-email-protection/review/1/reject.json", {}],
        [:post, "/admin/plugins/disify-email-protection/review/1/recheck.json", {}],
        [:get, "/admin/plugins/disify-email-protection/tools.json", {}],
        [:get, "/admin/plugins/disify-email-protection/tools/scan/status.json", {}],
        [:post, "/admin/plugins/disify-email-protection/tools/check.json", { email: "member@example.com" }],
        [:post, "/admin/plugins/disify-email-protection/tools/scan.json", { scan_mode: "domain_only" }],
        [:post, "/admin/plugins/disify-email-protection/tools/scan/resume.json", {}],
        [:post, "/admin/plugins/disify-email-protection/tools/scan/cancel.json", {}],
        [:post, "/admin/plugins/disify-email-protection/exceptions.json", { kind: "allow_domain", disify_email_protection_exception_value: "example.com" }],
        [:delete, "/admin/plugins/disify-email-protection/exceptions/1.json", {}],
      ]

      requests.each do |method, path, params|
        public_send(method, path, params: params)
        expect(response.status).to eq(404).or eq(403), "expected #{method.upcase} #{path} to be admin-only"
      end
    end
  end

  describe "strict admin input validation" do
    it "rejects malformed record identifiers instead of coercing them to zero" do
      sign_in(admin)
      post "/admin/plugins/disify-email-protection/review/not-an-id/approve.json"
      expect(response.status).to eq(400)
    end

    it "bounds an excessively large review page to the available result set" do
      sign_in(admin)
      get "/admin/plugins/disify-email-protection/review.json", params: { state: "pending", page: "999999999999999999999" }
      expect(response.status).to eq(200)
      expect(response.parsed_body["page"]).to be >= 1
    end
  end

end

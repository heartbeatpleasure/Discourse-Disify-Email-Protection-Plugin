# frozen_string_literal: true

require "rails_helper"

RSpec.describe DisifyEmailProtection::ReviewQueue do
  fab!(:admin)
  fab!(:user)

  let(:email) { "member@example.com" }

  def build_review_item
    DisifyEmailProtection::ReviewItem.create!(
      user_id: user.id,
      email_domain: "example.com",
      email_hmac: DisifyEmailProtection::Normalizer.email_hmac(email),
      flow: "existing_user_scan",
      reason: "disposable",
      confidence: 100,
      signals: ["blacklist_exact"],
      state: "pending",
      metadata: { "source" => "api" },
    )
  end

  describe ".approve!" do
    it "creates only a temporary exact-email allow exception" do
      item = build_review_item

      described_class.approve!(item, admin)

      exception = DisifyEmailProtection::PolicyException.order(:id).last
      expect(exception.kind).to eq("allow_email_hmac")
      expect(exception.value).to eq(item.email_hmac)
      expect(exception.expires_at).to be_present
      expect(exception.expires_at).to be_within(5.seconds).of(7.days.from_now)
      expect(item.reload.metadata["resolution"]).to eq("allow_7_days")
    end
  end

  describe ".approve_permanently!" do
    it "permanently allows only the exact reviewed email HMAC, not the domain" do
      item = build_review_item

      described_class.approve_permanently!(item, admin)

      exception = DisifyEmailProtection::PolicyException.order(:id).last
      expect(exception.kind).to eq("allow_email_hmac")
      expect(exception.value).to eq(item.email_hmac)
      expect(exception.expires_at).to be_nil
      expect(item.reload.state).to eq("approved")
      expect(item.metadata["resolution"]).to eq("allow_permanent")
      expect(DisifyEmailProtection::PolicyExceptions.decision_for(email)).to eq("bypass")
      expect(
        DisifyEmailProtection::PolicyExceptions.decision_for("other@example.com"),
      ).to be_nil

      expect { described_class.reject!(item, admin) }.to raise_error(Discourse::InvalidParameters)
      expect(
        DisifyEmailProtection::PolicyException.where(value: item.email_hmac).count,
      ).to eq(1)
    end
  end


  describe ".enqueue_create_or_refresh!" do
    it "queues only a privacy-safe fingerprint payload for validation reviews" do
      SiteSetting.disify_email_protection_review_queue_enabled = true
      email = "queued-review@example.com"
      expect(Jobs::DisifyEmailProtectionCreateReview).to receive(:perform_async) do |payload|
        expect(payload["email_hmac"]).to eq(DisifyEmailProtection::Normalizer.email_hmac(email))
        expect(payload["email_domain"]).to eq("example.com")
        expect(payload["user_id"]).to be_nil
        expect(payload["current_site_id"]).to eq(RailsMultisite::ConnectionManagement.current_db)
        expect(payload.to_json).not_to include(email)
        "jid-123"
      end

      expect(
        described_class.enqueue_create_or_refresh!(
          email: email,
          user: nil,
          flow: "signup",
          reason: "disposable",
          confidence: 100,
          signals: ["blacklist_exact"],
          metadata: { "source" => "api" },
        ),
      ).to eq(true)
    end
  end



  it "refuses to recreate a fingerprint after the linked user has been anonymized" do
    user.primary_email.update_columns(
      email: "anon#{user.id}@anonymized.invalid",
      normalized_email: "anon#{user.id}@anonymized.invalid",
    )

    result =
      described_class.create_or_refresh_from_fingerprint!(
        email_hmac: DisifyEmailProtection::Normalizer.email_hmac(email),
        email_domain: "example.com",
        user: user,
        flow: "email_change",
        reason: "disposable",
        confidence: 100,
        signals: [],
        metadata: {},
      )

    expect(result).to be_nil
    expect(DisifyEmailProtection::ReviewItem.where(user_id: user.id)).to be_empty
  end

  it "rejects review decisions from non-admin actors" do
    item = build_review_item
    expect { described_class.approve!(item, user) }.to raise_error(Discourse::InvalidAccess)
    expect(item.reload.state).to eq("pending")
  end

end

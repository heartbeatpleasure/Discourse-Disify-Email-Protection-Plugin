# frozen_string_literal: true

require "rails_helper"

RSpec.describe DisifyEmailProtection::RemediationManager do
  fab!(:admin)
  fab!(:user)

  before do
    SiteSetting.disify_email_protection_enabled = true
    SiteSetting.disify_email_protection_existing_user_remediation_enabled = true
    SiteSetting.disify_email_protection_remediation_grace_period_days = 60
    SiteSetting.disify_email_protection_remediation_after_grace = "restrict_account"
  end

  def set_primary_email!(value)
    user.primary_email.update_columns(email: value, normalized_email: UserEmail.normalize(value))
    user.reload
  end

  def review_item(email: user.email, reason: "disposable", state: "pending", resolution: nil)
    DisifyEmailProtection::ReviewItem.create!(
      user_id: user.id,
      email_domain: DisifyEmailProtection::Normalizer.domain(email),
      email_hmac: DisifyEmailProtection::Normalizer.email_hmac(email),
      flow: "existing_user_scan",
      reason: reason,
      confidence: 100,
      signals: ["blacklist_exact"],
      state: state,
      metadata: resolution ? { "resolution" => resolution } : {},
    )
  end

  describe ".require_change!" do
    it "creates a user remediation without creating a policy block" do
      item = review_item

      remediation = described_class.require_change!(item, admin)

      expect(remediation.user_id).to eq(user.id)
      expect(remediation.email_hmac).to eq(item.email_hmac)
      expect(remediation.state).to eq("required")
      expect(remediation.active).to eq(true)
      expect(remediation.enforce_at).to be_within(5.seconds).of(60.days.from_now)
      expect(item.reload.state).to eq("remediation")
      expect(item.metadata["resolution"]).to eq("email_change_required")
      expect(DisifyEmailProtection::PolicyException.where(value: item.email_hmac)).to be_empty
    end

    it "converts a legacy rejected existing-user item only when explicitly allowed" do
      item = review_item(state: "rejected", resolution: "block_30_days")

      expect do
        described_class.require_change!(item, admin)
      end.to raise_error(Discourse::InvalidParameters)

      remediation = described_class.require_change!(item, admin, allow_legacy_rejected: true)
      expect(remediation).to be_present
      expect(item.reload.metadata["previous_resolution"]).to eq("block_30_days")
      expect(item.metadata["resolution"]).to eq("email_change_required")
    end

    it "refuses a stale review after the user already changed email" do
      item = review_item
      set_primary_email!("new-current@example.org")

      expect do
        described_class.require_change!(item, admin)
      end.to raise_error(Discourse::InvalidParameters)
      expect(DisifyEmailProtection::EmailRemediation.where(user_id: user.id)).to be_empty
    end

    it "closes duplicate pending existing-user reviews for the same current email" do
      item = review_item(reason: "disposable")
      duplicate = review_item(reason: "no_mx")

      remediation = described_class.require_change!(item, admin)

      duplicate.reload
      expect(duplicate.state).to eq("expired")
      expect(duplicate.metadata["resolution"]).to eq("superseded_by_email_change_requirement")
      expect(duplicate.metadata["remediation_id"]).to eq(remediation.id)
    end
  end

  describe ".restriction_applies?" do
    it "restricts a non-staff user only after the grace period while the reviewed email is still current" do
      item = review_item
      remediation = described_class.require_change!(item, admin)
      remediation.update!(enforce_at: 1.minute.ago)

      expect(described_class.restriction_applies?(user.reload, remediation.reload)).to eq(true)

      set_primary_email!("replacement@example.org")
      expect(described_class.restriction_applies?(user.reload, remediation.reload)).to eq(false)
    end
  end

  describe ".process_current_email!" do
    it "releases enforcement immediately and keeps verification pending when DISIFY is unavailable" do
      item = review_item
      remediation = described_class.require_change!(item, admin)
      remediation.update!(enforce_at: 1.minute.ago)
      set_primary_email!("replacement@example.org")

      unavailable = DisifyEmailProtection::Decision::DecisionResult.new(
        decision: "fail_open",
        reason: "timeout",
        confidence: nil,
        signals: [],
        source: "api",
        status: "unavailable",
        payload: {},
      )
      allow(DisifyEmailProtection::Decision).to receive(:evaluate).and_return(unavailable)
      allow(Jobs).to receive(:enqueue_in)

      described_class.process_current_email!(user.reload)

      remediation.reload
      expect(remediation.state).to eq("verification_pending")
      expect(remediation.email_hmac).to eq(
        DisifyEmailProtection::Normalizer.email_hmac("replacement@example.org"),
      )
      expect(described_class.restriction_applies?(user.reload, remediation)).to eq(false)
      expect(Jobs).to have_received(:enqueue_in).with(
        1.hour,
        :disify_email_protection_verify_remediation,
        { remediation_id: remediation.id },
      )
    end


    it "marks the originating review resolved after a verified replacement email" do
      item = review_item
      remediation = described_class.require_change!(item, admin)
      set_primary_email!("verified-replacement@example.org")

      clean = DisifyEmailProtection::Decision::DecisionResult.new(
        decision: "allow",
        reason: "clean",
        confidence: 100,
        signals: [],
        source: "api",
        status: "success",
        payload: {},
      )
      allow(DisifyEmailProtection::Decision).to receive(:evaluate).and_return(clean)
      allow(DisifyEmailProtection::UserNoteWriter).to receive(:record!)

      described_class.process_current_email!(user.reload)

      expect(remediation.reload.active).to eq(false)
      expect(remediation.resolution).to eq("email_changed_verified")
      expect(item.reload.metadata["resolution"]).to eq("email_change_resolved")
    end

    it "does not record a resolved note if the current email changes during the final resolution check" do
      item = review_item
      described_class.require_change!(item, admin)
      set_primary_email!("verified-replacement@example.org")

      clean = DisifyEmailProtection::Decision::DecisionResult.new(
        decision: "allow",
        reason: "clean",
        confidence: 100,
        signals: [],
        source: "api",
        status: "success",
        payload: {},
      )
      allow(DisifyEmailProtection::Decision).to receive(:evaluate).and_return(clean)
      allow(described_class).to receive(:resolve_if_current!).and_return(false)
      expect(DisifyEmailProtection::UserNoteWriter).not_to receive(:record!)

      described_class.process_current_email!(user.reload)
    end
  end


  describe ".verify_pending!" do
    it "does not put an email HMAC in the Sidekiq payload and respects normal circuit-breaker handling" do
      item = review_item
      remediation = described_class.require_change!(item, admin)
      set_primary_email!("replacement@example.org")
      remediation.update!(
        email_hmac: DisifyEmailProtection::Normalizer.email_hmac(user.reload.email),
        email_domain: DisifyEmailProtection::Normalizer.domain(user.email),
        state: "verification_pending",
      )

      clean = DisifyEmailProtection::Decision::DecisionResult.new(
        decision: "allow",
        reason: "clean",
        confidence: 100,
        signals: [],
        source: "api",
        status: "success",
        payload: {},
      )
      expect(DisifyEmailProtection::Decision).to receive(:evaluate).with(
        hash_including(
          email: "replacement@example.org",
          flow: "remediation_recheck",
          force_remote: false,
        ),
      ).and_return(clean)
      allow(DisifyEmailProtection::UserNoteWriter).to receive(:record!)

      expect(described_class.verify_pending!(remediation.id)).to eq(true)
      expect(remediation.reload.active).to eq(false)
    end
  end

  describe ".self_service_email_change_available?" do
    it "prevents hard restriction when Discourse does not allow the user to edit email" do
      item = review_item
      remediation = described_class.require_change!(item, admin)
      remediation.update!(enforce_at: 1.minute.ago)

      SiteSetting.auth_overrides_email = true
      expect(described_class.self_service_email_change_available?(user.reload)).to eq(false)
      expect(described_class.restriction_applies?(user.reload, remediation.reload)).to eq(false)
    end
  end

  describe ".bulk_candidate_scope" do
    it "excludes role-address reviews from the bulk action while retaining them for manual remediation" do
      disposable = review_item(reason: "disposable")
      role = review_item(reason: "role")

      expect(described_class.eligible_existing_user_review?(role)).to eq(true)
      expect(described_class.bulk_candidate_scope("pending")).to include(disposable)
      expect(described_class.bulk_candidate_scope("pending")).not_to include(role)
      expect(described_class.bulk_candidate_ids("pending")).to eq([disposable.id])
    end
  end
end

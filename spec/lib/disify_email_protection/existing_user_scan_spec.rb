# frozen_string_literal: true

require "rails_helper"

RSpec.describe DisifyEmailProtection::ExistingUserScan do
  fab!(:admin)

  before do
    SiteSetting.disify_email_protection_enabled = true
    SiteSetting.disify_email_protection_manual_scan_enabled = true
  end

  after do
    PluginStore.remove(DisifyEmailProtection::STORE_NAMESPACE, described_class::STATE_KEY)
  end

  it "pauses a stale running scan instead of leaving it stuck" do
    PluginStore.set(
      DisifyEmailProtection::STORE_NAMESPACE,
      described_class::STATE_KEY,
      {
        "scan_id" => "stale-scan",
        "status" => "running",
        "started_at" => 20.minutes.ago.iso8601,
        "last_activity_at" => 20.minutes.ago.iso8601,
      },
    )

    state = described_class.state

    expect(state["status"]).to eq("paused")
    expect(state["last_error"]).to eq("stale_scan")
    expect(state["next_run_at"]).to be_nil
  end

  it "does not mark a waiting scan stale while its next run is still in the future" do
    PluginStore.set(
      DisifyEmailProtection::STORE_NAMESPACE,
      described_class::STATE_KEY,
      {
        "scan_id" => "waiting-scan",
        "status" => "waiting",
        "started_at" => 30.minutes.ago.iso8601,
        "last_activity_at" => 30.minutes.ago.iso8601,
        "next_run_at" => 20.minutes.from_now.iso8601,
      },
    )

    expect(described_class.state["status"]).to eq("waiting")
  end

  it "cancels an active scan without deleting queued jobs" do
    PluginStore.set(
      DisifyEmailProtection::STORE_NAMESPACE,
      described_class::STATE_KEY,
      {
        "scan_id" => "active-scan",
        "status" => "running",
        "started_at" => 1.minute.ago.iso8601,
        "last_activity_at" => Time.zone.now.iso8601,
      },
    )

    state = described_class.cancel!(actor: admin)

    expect(state["status"]).to eq("cancelled")
    expect(state["cancelled_by_id"]).to eq(admin.id)
    expect(described_class.still_active?("active-scan")).to eq(false)
  end
  it "treats duplicate start requests with the same request id as one scan" do
    allow(Jobs).to receive(:enqueue)

    first = described_class.start!(
      actor: admin,
      scan_mode: "domain_only",
      request_id: "same-confirmation",
    )
    second = described_class.start!(
      actor: admin,
      scan_mode: "domain_only",
      request_id: "same-confirmation",
    )

    expect(second["scan_id"]).to eq(first["scan_id"])
    expect(second["start_request_id"]).to eq("same-confirmation")
    expect(Jobs).to have_received(:enqueue).once
  end

  it "loads all Disify background job classes" do
    expect(defined?(Jobs::DisifyExistingUserScan)).to eq("constant")
    expect(defined?(Jobs::DisifyEmailProtectionCreateReview)).to eq("constant")
    expect(defined?(Jobs::DisifyEmailProtectionRecordValidationResult)).to eq("constant")
    expect(defined?(Jobs::DisifyEmailProtectionAnonymizeCleanup)).to eq("constant")
    expect(defined?(Jobs::DisifyEmailProtectionCleanup)).to eq("constant")
    expect(defined?(Jobs::DisifyEmailProtectionHealthCheck)).to eq("constant")
    expect(defined?(Jobs::DisifyEmailProtectionModeratorDigest)).to eq("constant")
  end

  it "pauses a newly created scan when enqueueing fails" do
    allow(Jobs).to receive(:enqueue).and_raise(StandardError, "queue unavailable")

    expect do
      described_class.start!(
        actor: admin,
        scan_mode: "domain_only",
        request_id: "enqueue-failure",
      )
    end.to raise_error(StandardError, "queue unavailable")

    state = described_class.state
    expect(state["status"]).to eq("paused")
    expect(state["last_error"]).to eq("enqueue_failed")
    expect(state["processed"]).to eq(0)
  end

  it "pauses a resumed scan when enqueueing fails" do
    PluginStore.set(
      DisifyEmailProtection::STORE_NAMESPACE,
      described_class::STATE_KEY,
      {
        "scan_id" => "resume-enqueue-failure",
        "status" => "paused",
        "started_at" => 1.minute.ago.iso8601,
        "last_activity_at" => Time.zone.now.iso8601,
      },
    )
    allow(Jobs).to receive(:enqueue).and_raise(StandardError, "queue unavailable")

    expect { described_class.resume!(actor: admin) }.to raise_error(StandardError, "queue unavailable")

    state = described_class.state
    expect(state["status"]).to eq("paused")
    expect(state["last_error"]).to eq("enqueue_failed")
  end

  it "checkpoints progress so a long active batch keeps a fresh heartbeat" do
    current = {
      "scan_id" => "checkpoint-scan",
      "status" => "running",
      "cursor" => 25,
      "processed" => 20,
      "flagged" => 2,
      "last_activity_at" => 20.minutes.ago.iso8601,
    }
    PluginStore.set(
      DisifyEmailProtection::STORE_NAMESPACE,
      described_class::STATE_KEY,
      current.merge("cursor" => 10, "processed" => 10, "flagged" => 1),
    )

    expect(described_class.checkpoint_progress_if_active!(current, "checkpoint-scan")).to eq(true)
    state = described_class.raw_state
    expect(state["cursor"]).to eq(25)
    expect(state["processed"]).to eq(20)
    expect(state["flagged"]).to eq(2)
    expect(Time.zone.parse(state["last_activity_at"])).to be > 1.minute.ago
  end

  it "rejects control characters in a scan request id" do
    expect do
      described_class.start!(actor: admin, scan_mode: "domain_only", request_id: "bad\nrequest")
    end.to raise_error(Discourse::InvalidParameters)
  end

  it "proactively pauses large scans before exhausting the last provider request slot" do
    PluginStore.set(
      DisifyEmailProtection::STORE_NAMESPACE,
      DisifyEmailProtection::Health::HEALTH_KEY,
      { "rate_limit_limit" => 10, "rate_limit_remaining" => 1 },
    )

    expect(described_class.provider_rate_limit_nearly_exhausted?).to eq(true)
  ensure
    PluginStore.remove(DisifyEmailProtection::STORE_NAMESPACE, DisifyEmailProtection::Health::HEALTH_KEY)
  end

  it "lets only one worker claim a queued scan token" do
    token = "0123456789abcdef"
    PluginStore.set(
      DisifyEmailProtection::STORE_NAMESPACE,
      described_class::STATE_KEY,
      {
        "scan_id" => "claim-scan",
        "status" => "running",
        "started_at" => Time.zone.now.iso8601,
        "last_activity_at" => Time.zone.now.iso8601,
        "queued_job_token" => token,
      },
    )

    first = described_class.claim_job!("claim-scan", token)
    second = described_class.claim_job!("claim-scan", token)

    expect(first).to be_present
    expect(first.last).to eq(token)
    expect(second).to be_nil
    expect(described_class.raw_state["active_job_token"]).to eq(token)
  end

  it "prevents a stale worker from checkpointing over a newer active generation" do
    PluginStore.set(
      DisifyEmailProtection::STORE_NAMESPACE,
      described_class::STATE_KEY,
      {
        "scan_id" => "fenced-scan",
        "status" => "running",
        "cursor" => 50,
        "processed" => 50,
        "flagged" => 5,
        "last_activity_at" => Time.zone.now.iso8601,
        "active_job_token" => "1111111111111111",
      },
    )
    stale = { "cursor" => 100, "processed" => 100, "flagged" => 10 }

    expect(
      described_class.checkpoint_progress_if_active!(
        stale,
        "fenced-scan",
        "2222222222222222",
      ),
    ).to eq(false)

    state = described_class.raw_state
    expect(state["cursor"]).to eq(50)
    expect(state["processed"]).to eq(50)
    expect(state["flagged"]).to eq(5)
  end


  it "pauses a queued scan without contacting DISIFY when the plugin is disabled" do
    token = "0123456789abcdef"
    PluginStore.set(
      DisifyEmailProtection::STORE_NAMESPACE,
      described_class::STATE_KEY,
      {
        "scan_id" => "disabled-scan",
        "status" => "running",
        "started_at" => Time.zone.now.iso8601,
        "last_activity_at" => Time.zone.now.iso8601,
        "queued_job_token" => token,
        "cursor" => 0,
        "processed" => 0,
        "flagged" => 0,
      },
    )
    SiteSetting.disify_email_protection_enabled = false
    expect(DisifyEmailProtection::Decision).not_to receive(:evaluate)

    described_class.process_batch!("disabled-scan", token)

    state = described_class.state
    expect(state["status"]).to eq("paused")
    expect(state["last_error"]).to eq("plugin_disabled")
  end

  it "skips anonymized users without contacting DISIFY or creating a review" do
    anonymized = Fabricate(:user)
    anonymized.primary_email.update_columns(
      email: "anon#{anonymized.id}@anonymized.invalid",
      normalized_email: "anon#{anonymized.id}@anonymized.invalid",
    )

    token = "fedcba9876543210"
    PluginStore.set(
      DisifyEmailProtection::STORE_NAMESPACE,
      described_class::STATE_KEY,
      {
        "scan_id" => "anonymized-scan",
        "status" => "running",
        "started_at" => Time.zone.now.iso8601,
        "last_activity_at" => Time.zone.now.iso8601,
        "queued_job_token" => token,
        "cursor" => anonymized.id - 1,
        "processed" => 0,
        "flagged" => 0,
        "mode" => "domain_only",
      },
    )

    allow(DisifyEmailProtection::CircuitBreaker).to receive(:open?).and_return(false)
    expect(DisifyEmailProtection::Decision).not_to receive(:evaluate)
    expect(DisifyEmailProtection::ReviewQueue).not_to receive(:create_or_refresh!)
    allow(Jobs).to receive(:enqueue_in)

    described_class.process_batch!("anonymized-scan", token)

    state = described_class.raw_state
    expect(state["processed"]).to eq(1)
    expect(state["flagged"]).to eq(0)
    expect(state["cursor"]).to eq(anonymized.id)
  end

  it "does not flag role addresses when the configured role action is ignore" do
    SiteSetting.disify_email_protection_role_email_action = "ignore"
    result = DisifyEmailProtection::Decision::DecisionResult.new(
      decision: "allow",
      reason: "role",
      confidence: 100,
      signals: ["role"],
      source: "cache",
      status: "success",
      payload: {},
    )

    expect(described_class.risky_result?(result)).to eq(false)
  end

  it "does not expose internal worker tokens in admin-facing scan state" do
    PluginStore.set(
      DisifyEmailProtection::STORE_NAMESPACE,
      described_class::STATE_KEY,
      {
        "scan_id" => "public-state-scan",
        "status" => "running",
        "last_activity_at" => Time.zone.now.iso8601,
        "queued_job_token" => "0123456789abcdef",
        "active_job_token" => nil,
      },
    )

    state = described_class.state
    expect(state).not_to have_key("queued_job_token")
    expect(state).not_to have_key("active_job_token")
  end

end

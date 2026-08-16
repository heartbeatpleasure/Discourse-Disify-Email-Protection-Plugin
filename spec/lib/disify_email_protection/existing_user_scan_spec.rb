# frozen_string_literal: true

require "rails_helper"

RSpec.describe DisifyEmailProtection::ExistingUserScan do
  fab!(:admin)

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

end

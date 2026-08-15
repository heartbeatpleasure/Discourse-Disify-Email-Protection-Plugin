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
end

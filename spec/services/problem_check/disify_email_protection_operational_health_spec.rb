# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProblemCheck::DisifyEmailProtectionOperationalHealth do
  before do
    SiteSetting.disify_email_protection_enabled = true
  end

  it "uses a persistent high-priority scheduled check" do
    expect(described_class.priority).to eq("high")
    expect(described_class.perform_every).to eq(10.minutes)
    expect(described_class.max_retries).to eq(0)
    expect(described_class.max_blips).to eq(1)
  end

  it "returns no problem while health is healthy" do
    allow(DisifyEmailProtection::Health).to receive(:payload).and_return(
      overall: "healthy",
      provider: {},
      circuit_breaker: { state: "closed" },
    )

    expect(described_class.new.call).to be_nil
  end

  it "returns a problem while provider health is degraded" do
    allow(DisifyEmailProtection::Health).to receive(:payload).and_return(
      overall: "degraded",
      provider: { "last_error_code" => "read_timeout" },
      circuit_breaker: { state: "closed", reason: nil },
    )

    problem = described_class.new.call
    expect(problem).to be_present
    expect(problem.details[:status]).to eq("degraded")
    expect(problem.details[:reason]).to eq("read_timeout")
  end

  it "surfaces an internal health-check failure instead of silently passing" do
    allow(DisifyEmailProtection::Health).to receive(:payload).and_raise(StandardError, "boom")

    problem = described_class.new.call
    expect(problem).to be_present
    expect(problem.details[:status]).to eq("internal_error")
    expect(problem.details[:reason]).to eq("StandardError")
  end

end

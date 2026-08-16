# frozen_string_literal: true

require "rails_helper"

RSpec.describe DisifyEmailProtection::CircuitBreaker do
  after { described_class.reset! }

  it "does not let a late success cancel an active rate-limit backoff" do
    result = DisifyEmailProtection::Client::Result.new(
      success: false,
      error_code: :rate_limited,
      retry_after: 120,
    )
    described_class.record_failure!(result)
    original_deadline = described_class.open_until

    expect(described_class.record_success!).to eq(false)
    expect(described_class.open?).to eq(true)
    expect(described_class.open_until.to_i).to eq(original_deadline.to_i)
  end

  it "never shortens an already longer protection window" do
    longer = described_class.open_for!(10.minutes, "quota_exceeded")
    shorter = described_class.open_for!(30.seconds, "rate_limited")

    expect(shorter.to_i).to eq(longer.to_i)
    expect(described_class.open_until.to_i).to eq(longer.to_i)
  end

  it "allows a successful request to clear a non-rate-limit failure" do
    described_class.open_for!(5.minutes, "network_error")
    expect(described_class.record_success!).to eq(true)
    expect(described_class.open?).to eq(false)
  end
end

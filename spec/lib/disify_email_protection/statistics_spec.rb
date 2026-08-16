# frozen_string_literal: true

require "rails_helper"

RSpec.describe DisifyEmailProtection::Statistics do
  before { DisifyEmailProtection::DailyStat.delete_all }

  it "accumulates repeated checks in the current daily row" do
    described_class.increment!(checked: 1, api_calls: 1, allowed: 1)
    described_class.increment!(checked: 5, cache_hits: 4, monitored: 2, allowed: 3)

    payload = described_class.period_payload(7)

    expect(payload[:totals]).to include(
      checked: 6,
      api_calls: 1,
      cache_hits: 4,
      monitored: 2,
      allowed: 4,
    )
    expect(payload[:daily].last).to include(
      stat_date: Date.current.iso8601,
      checked: 6,
      api_calls: 1,
      cache_hits: 4,
    )
  end
end

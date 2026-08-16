# frozen_string_literal: true

require "rails_helper"

RSpec.describe Jobs::DisifyEmailProtectionReviewQueueNotification do
  it "checks the grouped review queue reminder independently" do
    expect(DisifyEmailProtection::ReviewQueueNotifier).to receive(:send_if_needed!).and_return(false)

    described_class.new.execute({})
  end
end

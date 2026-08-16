# frozen_string_literal: true

require "rails_helper"

RSpec.describe Jobs::DisifyEmailProtectionModeratorDigest do
  it "runs the activity digest and grouped review queue reminder independently" do
    expect(DisifyEmailProtection::ModeratorDigest).to receive(:send_if_needed!).and_return(false)
    expect(DisifyEmailProtection::ReviewQueueNotifier).to receive(:send_if_needed!).and_return(false)

    described_class.new.execute({})
  end
end

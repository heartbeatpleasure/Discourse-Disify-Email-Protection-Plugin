# frozen_string_literal: true

require "rails_helper"

RSpec.describe Jobs::DisifyEmailProtectionModeratorDigest do
  it "checks whether the scheduled activity digest is due" do
    expect(DisifyEmailProtection::ModeratorDigest).to receive(:send_if_needed!).and_return(false)

    described_class.new.execute({})
  end
end

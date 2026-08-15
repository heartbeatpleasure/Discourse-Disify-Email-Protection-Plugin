# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DISIFY UserEmail validation" do
  fab!(:user)

  before do
    SiteSetting.disify_email_protection_enabled = true
    SiteSetting.disify_email_protection_check_email_changes = true
    SiteSetting.disify_email_protection_mode = "enforce"
  end

  it "adds an email error when the decision blocks an address" do
    result = DisifyEmailProtection::Decision::DecisionResult.new(
      decision: "block",
      reason: "disposable",
      confidence: 100,
      signals: ["blacklist"],
      source: "api",
      status: "success",
      user_message_key: "disposable_email",
      payload: {},
    )
    allow(DisifyEmailProtection::Decision).to receive(:evaluate).and_return(result)

    email = UserEmail.new(user: user, email: "new-address@example.com", primary: false)

    expect(email).not_to be_valid
    expect(email.errors[:email].join(" ")).to include("cannot be used")
  end

  it "reuses a previous result but reapplies the blocking error on repeated validation" do
    result = DisifyEmailProtection::Decision::DecisionResult.new(
      decision: "block",
      reason: "disposable",
      confidence: 100,
      signals: ["blacklist"],
      source: "api",
      status: "success",
      user_message_key: "disposable_email",
      payload: {},
    )
    expect(DisifyEmailProtection::Decision).to receive(:evaluate).once.and_return(result)

    email = UserEmail.new(user: user, email: "repeat-check@example.com", primary: false)
    expect(email).not_to be_valid
    expect(email).not_to be_valid
    expect(email.errors[:email].join(" ")).to include("cannot be used")
  end

  it "does not call the external decision service when the plugin is disabled" do
    SiteSetting.disify_email_protection_enabled = false
    expect(DisifyEmailProtection::Decision).not_to receive(:evaluate)

    email = UserEmail.new(user: user, email: "new-address@example.com", primary: false)
    email.valid?
  end

  it "does not call the external decision service after a core email validation error" do
    expect(DisifyEmailProtection::Decision).not_to receive(:evaluate)

    email = UserEmail.new(user: user, email: "not-an-email", primary: false)
    email.valid?
  end
end

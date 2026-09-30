# frozen_string_literal: true

require "rails_helper"

RSpec.describe DisifyEmailProtection::RequestRestriction do
  fab!(:admin)
  fab!(:user)

  before do
    SiteSetting.disify_email_protection_enabled = true
    SiteSetting.disify_email_protection_existing_user_remediation_enabled = true
    SiteSetting.disify_email_protection_remediation_after_grace = "restrict_account"
  end

  def overdue_remediation(target_user = user)
    DisifyEmailProtection::EmailRemediation.create!(
      user_id: target_user.id,
      required_by_id: admin.id,
      email_hmac: DisifyEmailProtection::Normalizer.email_hmac(target_user.email),
      email_domain: DisifyEmailProtection::Normalizer.domain(target_user.email),
      reason: "disposable",
      confidence: 100,
      state: "required",
      active: true,
      required_at: 61.days.ago,
      enforce_at: 1.day.ago,
    )
  end

  def stub_request(controller, method: "POST", action_name: "create")
    allow(controller).to receive(:current_user).and_return(user)
    allow(controller).to receive(:request).and_return(
      double(request_method: method, format: double(json?: true), xhr?: true),
    )
    allow(controller).to receive(:action_name).and_return(action_name)
  end

  it "blocks a normal unsafe request after the grace period but keeps reads available" do
    remediation = overdue_remediation
    allow(DisifyEmailProtection::UserNoteWriter).to receive(:record!)

    write_controller = ApplicationController.new
    stub_request(write_controller)
    expect(write_controller).to receive(:render).with(
      hash_including(status: :forbidden),
    )

    expect(described_class.enforce!(write_controller)).to eq(true)
    expect(remediation.reload.restricted_at).to be_present

    read_controller = ApplicationController.new
    stub_request(read_controller, method: "GET")
    expect(read_controller).not_to receive(:render)
    expect(described_class.enforce!(read_controller)).to eq(false)
  end


  it "redirects a non-JSON write to email preferences instead of returning raw JSON" do
    overdue_remediation
    allow(DisifyEmailProtection::UserNoteWriter).to receive(:record!)
    controller = ApplicationController.new
    request = double(request_method: "POST", format: double(json?: false), xhr?: false)
    allow(controller).to receive(:current_user).and_return(user)
    allow(controller).to receive(:request).and_return(request)
    allow(controller).to receive(:flash).and_return({})
    allow(controller).to receive(:action_name).and_return("create")
    expect(controller).to receive(:redirect_to).with(
      "#{Discourse.base_path}/u/#{user.encoded_username}/preferences/email",
    )

    expect(described_class.enforce!(controller)).to eq(true)
  end

  it "allows trusted-session recovery requests that can be required before changing email" do
    overdue_remediation
    controller = UsersController.new
    stub_request(controller, action_name: "confirm_session")

    expect(controller).not_to receive(:render)
    expect(described_class.enforce!(controller)).to eq(false)
  end

  it "allows the Discourse email controller while the account is restricted" do
    overdue_remediation
    controller = UsersEmailController.new
    stub_request(controller, action_name: "update")

    expect(controller).not_to receive(:render)
    expect(described_class.enforce!(controller)).to eq(false)
  end

  it "never hard-restricts staff accounts" do
    staff = Fabricate(:admin)
    overdue_remediation(staff)
    controller = ApplicationController.new
    allow(controller).to receive(:current_user).and_return(staff)
    allow(controller).to receive(:request).and_return(double(request_method: "POST"))

    expect(controller).not_to receive(:render)
    expect(described_class.enforce!(controller)).to eq(false)
  end
end

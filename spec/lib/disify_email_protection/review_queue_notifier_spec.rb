# frozen_string_literal: true

require "rails_helper"

RSpec.describe DisifyEmailProtection::ReviewQueueNotifier do
  fab!(:admin)
  fab!(:moderator)

  let(:store) { {} }
  let(:staff_group) { instance_double(Group, name: "staff") }
  let(:human_users) { instance_double(ActiveRecord::Relation) }

  before do
    SiteSetting.disify_email_protection_enabled = true
    SiteSetting.disify_email_protection_review_queue_enabled = true
    SiteSetting.disify_email_protection_review_queue_notification_enabled = true
    SiteSetting.disify_email_protection_review_queue_notification_recipients = "staff"
    SiteSetting.disify_email_protection_review_queue_notification_interval_days = 30

    allow(PluginStore).to receive(:get) { |_namespace, key| store[key] }
    allow(PluginStore).to receive(:set) do |_namespace, key, value|
      store[key] = value
    end
    allow(Group).to receive(:[]).with(:staff).and_return(staff_group)
    allow(staff_group).to receive(:human_users).and_return(human_users)
    allow(human_users).to receive(:exists?).and_return(true)
  end

  def create_pending_review
    DisifyEmailProtection::ReviewItem.create!(
      user_id: admin.id,
      email_domain: "example.com",
      email_hmac: "a" * 64,
      flow: "existing_user_scan",
      reason: "disposable",
      confidence: 100,
      signals: ["blacklist_exact"],
      state: "pending",
      metadata: {},
    )
  end

  it "does not send a reminder when the queue is empty" do
    expect(PostCreator).not_to receive(:create!)

    expect(described_class.send_if_needed!).to eq(false)
  end

  it "sends one grouped private message containing only the pending count" do
    create_pending_review

    expect(PostCreator).to receive(:create!).with(
      Discourse.system_user,
      hash_including(
        target_group_names: ["staff"],
        archetype: Archetype.private_message,
        title: "Email protection review queue reminder",
        raw: include("**1** pending item"),
      ),
    ).and_return(instance_double(Post))

    expect(described_class.send_if_needed!).to eq(true)
    expect(store[described_class::LAST_SENT_KEY]).to be_present
  end

  it "does not send again before the configured interval" do
    create_pending_review
    store[described_class::LAST_SENT_KEY] = 10.days.ago.iso8601

    expect(PostCreator).not_to receive(:create!)

    expect(described_class.send_if_needed!).to eq(false)
  end

  it "sends again once the configured interval has elapsed" do
    create_pending_review
    store[described_class::LAST_SENT_KEY] = 31.days.ago.iso8601

    expect(PostCreator).to receive(:create!).and_return(instance_double(Post))

    expect(described_class.send_if_needed!).to eq(true)
  end

  it "maps the admins-and-moderators option to the automatic staff group" do
    create_pending_review
    expect(Group).to receive(:[]).with(:staff).and_return(staff_group)
    allow(PostCreator).to receive(:create!).and_return(instance_double(Post))

    expect(described_class.send_if_needed!).to eq(true)
  end

  it "does not send when notifications are disabled" do
    create_pending_review
    SiteSetting.disify_email_protection_review_queue_notification_enabled = false

    expect(PostCreator).not_to receive(:create!)

    expect(described_class.send_if_needed!).to eq(false)
  end
end

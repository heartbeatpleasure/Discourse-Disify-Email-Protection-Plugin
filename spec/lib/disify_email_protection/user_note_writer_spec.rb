# frozen_string_literal: true

require "rails_helper"

RSpec.describe DisifyEmailProtection::UserNoteWriter do
  after do
    PluginStoreRow.where(plugin_name: described_class::NOTE_NAMESPACE).delete_all
  end

  it "removes expired or malformed debounce state while preserving recent state" do
    PluginStore.set(described_class::NOTE_NAMESPACE, "1:old:example.com:test", 2.days.ago.iso8601)
    PluginStore.set(described_class::NOTE_NAMESPACE, "1:recent:example.com:test", 1.hour.ago.iso8601)
    PluginStore.set(described_class::NOTE_NAMESPACE, "1:invalid:example.com:test", "not-a-time")

    expect(described_class.cleanup_stale_debounce!(now: Time.zone.now)).to eq(2)
    expect(PluginStore.get(described_class::NOTE_NAMESPACE, "1:old:example.com:test")).to be_nil
    expect(PluginStore.get(described_class::NOTE_NAMESPACE, "1:invalid:example.com:test")).to be_nil
    expect(PluginStore.get(described_class::NOTE_NAMESPACE, "1:recent:example.com:test")).to be_present
  end
end

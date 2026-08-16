# frozen_string_literal: true

require "rails_helper"

RSpec.describe DisifyEmailProtection::Client do
  subject(:client) { described_class.new }

  let(:valid_payload) do
    {
      "format" => true,
      "domain" => "example.com",
      "disposable" => false,
      "dns" => true,
      "confidence" => 100,
    }
  end

  describe "provider payload validation" do
    it "rejects non-boolean optional flags instead of coercing strings to true" do
      payload = valid_payload.merge("role" => "false")
      expect(client.send(:valid_success_payload?, payload)).to eq(false)
    end

    it "treats omitted optional booleans as false" do
      sanitized = client.send(:sanitize_payload, valid_payload)
      expect(sanitized["role"]).to eq(false)
      expect(sanitized["alias"]).to eq(false)
    end

    it "drops malformed or oversized signal tokens" do
      payload = valid_payload.merge(
        "signals" => ["blacklist_exact", "<script>", "x" * 65],
      )
      sanitized = client.send(:sanitize_payload, payload)
      expect(sanitized["signals"]).to eq(["blacklist_exact"])
    end
  end

  describe "bounded response reading" do
    it "stops streaming before an oversized response is accumulated" do
      response = instance_double(Net::HTTPResponse)
      allow(response).to receive(:[]).with("Content-Length").and_return(nil)
      allow(response).to receive(:read_body).and_yield("a" * (described_class::MAX_BODY_BYTES + 1))

      expect { client.send(:read_bounded_body, response) }.to raise_error(
        DisifyEmailProtection::Client::ResponseTooLarge,
      )
    end

    it "rejects an oversized declared content length before reading the body" do
      response = instance_double(Net::HTTPResponse)
      allow(response).to receive(:[]).with("Content-Length").and_return(
        (described_class::MAX_BODY_BYTES + 1).to_s,
      )
      expect(response).not_to receive(:read_body)

      expect { client.send(:read_bounded_body, response) }.to raise_error(
        DisifyEmailProtection::Client::ResponseTooLarge,
      )
    end
  end
end

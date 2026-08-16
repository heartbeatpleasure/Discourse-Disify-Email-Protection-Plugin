# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "uri"

module ::DisifyEmailProtection
  class Client
    class ResponseTooLarge < StandardError; end
    class InvalidCredential < StandardError; end

    Result = Struct.new(
      :success,
      :status,
      :payload,
      :error_code,
      :error_message,
      :latency_ms,
      :rate_limit_limit,
      :rate_limit_remaining,
      :retry_after,
      :reset_at,
      keyword_init: true,
    )

    MAX_BODY_BYTES = 256 * 1024
    MAX_DOMAIN_BYTES = 255
    MAX_SIGNAL_COUNT = 20
    MAX_SIGNAL_BYTES = 64
    MAX_TYPO_SUGGESTION_BYTES = 320
    OPTIONAL_BOOLEAN_FIELDS = %w[whitelist role free alias].freeze
    SIGNAL_PATTERN = /\A[a-z0-9_.:-]+\z/i
    USER_AGENT = "Discourse-Disify-Email-Protection/#{PLUGIN_VERSION}"

    def check_email(email)
      post_form("email", { email: email })
    end

    def check_domain(domain)
      post_form("domain", { domain: domain })
    end

    private

    def post_form(path, params)
      uri = URI.parse("#{API_BASE_URL}/#{path}")
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.min_version = OpenSSL::SSL::TLS1_2_VERSION if http.respond_to?(:min_version=)
      timeout_seconds = [[SiteSetting.disify_email_protection_timeout_ms.to_i, 500].max, 5000].min / 1000.0
      http.open_timeout = timeout_seconds
      http.read_timeout = timeout_seconds
      http.write_timeout = timeout_seconds if http.respond_to?(:write_timeout=)

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Accept"] = "application/json"
      request["User-Agent"] = USER_AGENT
      apply_authentication!(request)
      request.set_form_data(params)

      response = nil
      body = nil
      http.request(request) do |http_response|
        response = http_response
        body = read_bounded_body(http_response)
      end

      latency = elapsed_ms(started)
      parsed = parse_json(body)
      metadata = response_metadata(response, parsed, latency)
      status = response.code.to_i

      if status == 200 && parsed.is_a?(Hash) && parsed["error"].blank?
        raise JSON::ParserError, "missing or invalid result fields" unless valid_success_payload?(parsed)

        return Result.new(
          **metadata,
          success: true,
          status: status,
          payload: sanitize_payload(parsed),
        )
      end

      Result.new(
        **metadata,
        success: false,
        status: status,
        payload: {},
        error_code: error_code_for(status, parsed),
        error_message: safe_error_message(parsed),
      )
    rescue Net::OpenTimeout
      failure_result(:connect_timeout, started)
    rescue Net::ReadTimeout
      failure_result(:read_timeout, started)
    rescue OpenSSL::SSL::SSLError
      failure_result(:tls_error, started)
    rescue SocketError
      failure_result(:dns_error, started)
    rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH
      failure_result(:network_error, started)
    rescue ResponseTooLarge
      failure_result(:response_too_large, started)
    rescue InvalidCredential
      failure_result(:invalid_key, started)
    rescue JSON::ParserError
      failure_result(:parse_error, started)
    rescue StandardError => e
      Rails.logger.warn("[disify_email_protection] DISIFY request failed class=#{e.class}")
      failure_result(:network_error, started)
    end

    def apply_authentication!(request)
      key = SiteSetting.disify_email_protection_api_key.to_s.strip
      return if key.blank?

      # Net::HTTP rejects newlines in header values; reject control characters and
      # unreasonable credential sizes earlier so malformed configuration never
      # becomes a header-splitting or resource issue.
      raise InvalidCredential if key.bytesize > 1024 || key.match?(/[[:cntrl:]]/)

      if SiteSetting.disify_email_protection_api_auth_mode.to_s == "bearer"
        request["Authorization"] = "Bearer #{key}"
      else
        request["X-Api-Key"] = key
      end
    end

    def read_bounded_body(response)
      content_length = Integer(response["Content-Length"], exception: false)
      raise ResponseTooLarge if content_length.present? && content_length > MAX_BODY_BYTES

      body = +""
      response.read_body do |chunk|
        raise ResponseTooLarge if body.bytesize + chunk.bytesize > MAX_BODY_BYTES

        body << chunk
      end
      body
    end

    def parse_json(body)
      return {} if body.blank?

      JSON.parse(body)
    end

    def valid_success_payload?(payload)
      return false unless payload.key?("format") && boolean?(payload["format"])
      return false unless valid_provider_domain?(payload["domain"])
      return false unless payload.key?("disposable") && boolean?(payload["disposable"])
      return false unless payload.key?("dns") && boolean?(payload["dns"])
      return false unless OPTIONAL_BOOLEAN_FIELDS.all? { |field| !payload.key?(field) || boolean?(payload[field]) }
      return false if payload.key?("signals") && !valid_signals?(payload["signals"])

      confidence = payload["confidence"]
      confidence.is_a?(Integer) && confidence.between?(0, 100)
    end

    def sanitize_payload(payload)
      {
        "format" => payload["format"] == true,
        "domain" => payload["domain"].to_s.strip.downcase.presence,
        "disposable" => payload["disposable"] == true,
        "dns" => payload["dns"] == true,
        "whitelist" => payload["whitelist"] == true,
        "role" => payload["role"] == true,
        "free" => payload["free"] == true,
        "alias" => payload["alias"] == true,
        "confidence" => integer_or_nil(payload["confidence"]),
        "signals" => sanitize_signals(payload["signals"]),
        "typo_suggestion" => sanitize_typo_suggestion(payload["typo_suggestion"]),
      }.compact
    end

    def boolean?(value)
      value == true || value == false
    end

    def valid_provider_domain?(value)
      return false unless value.is_a?(String)

      domain = value.strip
      return false if domain.blank? || domain.bytesize > MAX_DOMAIN_BYTES
      return false if domain.match?(/[[:cntrl:]\s\/@]/)

      true
    end

    def valid_signals?(value)
      value.is_a?(Array) &&
        value.length <= 100 &&
        value.all? { |signal| signal.is_a?(String) && signal.bytesize <= 256 }
    end

    def sanitize_signals(value)
      Array(value).filter_map do |signal|
        next unless signal.is_a?(String)

        token = signal.strip
        next if token.blank? || token.bytesize > MAX_SIGNAL_BYTES || !SIGNAL_PATTERN.match?(token)

        token
      end.first(MAX_SIGNAL_COUNT)
    end

    def sanitize_typo_suggestion(value)
      return nil unless SiteSetting.disify_email_protection_typo_suggestions_enabled
      return nil unless value.is_a?(String)

      suggestion = value.strip
      return nil if suggestion.blank? || suggestion.bytesize > MAX_TYPO_SUGGESTION_BYTES
      return nil unless EmailAddressValidator.valid_value?(suggestion)

      suggestion
    end

    def response_metadata(response, parsed, latency)
      parsed_hash = parsed.is_a?(Hash) ? parsed : {}
      {
        latency_ms: latency,
        rate_limit_limit: nonnegative_integer_or_nil(response["X-RateLimit-Limit"]),
        rate_limit_remaining: nonnegative_integer_or_nil(response["X-RateLimit-Remaining"]),
        retry_after: nonnegative_integer_or_nil(response["Retry-After"] || parsed_hash["retry_after"]),
        reset_at: parse_time(parsed_hash["reset_at"]),
      }
    end

    def error_code_for(status, parsed)
      message = parsed.is_a?(Hash) ? parsed["error"].to_s.downcase : ""
      return :invalid_key if status == 401
      return :access_denied if status == 403
      if status == 429
        return :quota_exceeded if parsed.is_a?(Hash) && parsed["reset_at"].present?
        return :rate_limited
      end
      return :payload_too_large if status == 413
      return :unprocessable if status == 422
      return :server_error if status >= 500
      return :redirect if status.between?(300, 399)
      return :http_error if status >= 400
      return :api_error if message.present?

      :unexpected_response
    end

    def safe_error_message(parsed)
      return nil unless parsed.is_a?(Hash)

      parsed["error"].to_s.gsub(/[[:cntrl:]]+/, " ").squish.truncate(160).presence
    end

    def failure_result(code, started)
      Result.new(
        success: false,
        status: nil,
        payload: {},
        error_code: code,
        error_message: nil,
        latency_ms: elapsed_ms(started),
        rate_limit_limit: nil,
        rate_limit_remaining: nil,
        retry_after: nil,
        reset_at: nil,
      )
    end

    def elapsed_ms(started)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    end

    def integer_or_nil(value)
      Integer(value, exception: false)
    end

    def nonnegative_integer_or_nil(value)
      integer = integer_or_nil(value)
      integer.present? && integer >= 0 ? integer : nil
    end

    def parse_time(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end

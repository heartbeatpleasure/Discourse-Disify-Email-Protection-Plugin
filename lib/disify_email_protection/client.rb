# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "uri"

module ::DisifyEmailProtection
  class Client
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
      response = nil

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      timeout_seconds = [[SiteSetting.disify_email_protection_timeout_ms.to_i, 500].max, 5000].min / 1000.0
      http.open_timeout = timeout_seconds
      http.read_timeout = timeout_seconds
      http.write_timeout = timeout_seconds if http.respond_to?(:write_timeout=)

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Accept"] = "application/json"
      request["User-Agent"] = USER_AGENT
      apply_authentication!(request)
      request.set_form_data(params)

      response = http.request(request)
      latency = elapsed_ms(started)
      body = bounded_body(response)
      parsed = parse_json(body)

      metadata = response_metadata(response, parsed, latency)
      status = response.code.to_i

      if status == 200 && parsed.is_a?(Hash) && parsed["error"].blank?
        raise JSON::ParserError, "missing required result fields" unless valid_success_payload?(parsed)

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
    rescue JSON::ParserError
      failure_result(:parse_error, started)
    rescue StandardError => e
      Rails.logger.warn("[disify_email_protection] DISIFY request failed class=#{e.class}")
      failure_result(:network_error, started)
    end

    def apply_authentication!(request)
      key = SiteSetting.disify_email_protection_api_key.to_s.strip
      return if key.blank?

      if SiteSetting.disify_email_protection_api_auth_mode.to_s == "bearer"
        request["Authorization"] = "Bearer #{key}"
      else
        request["X-Api-Key"] = key
      end
    end

    def bounded_body(response)
      content_length = response["Content-Length"].to_i
      raise JSON::ParserError, "response too large" if content_length > MAX_BODY_BYTES

      body = response.body.to_s
      raise JSON::ParserError, "response too large" if body.bytesize > MAX_BODY_BYTES

      body
    end

    def parse_json(body)
      return {} if body.blank?

      JSON.parse(body)
    end

    def valid_success_payload?(payload)
      return false unless payload.key?("format") && [true, false].include?(payload["format"])
      return false unless payload["domain"].is_a?(String) && payload["domain"].present?
      return false unless payload.key?("disposable") && [true, false].include?(payload["disposable"])
      return false unless payload.key?("dns") && [true, false].include?(payload["dns"])

      confidence = integer_or_nil(payload["confidence"])
      confidence.present? && confidence.between?(0, 100)
    end

    def sanitize_payload(payload)
      {
        "format" => !!payload["format"],
        "domain" => payload["domain"].to_s.downcase.presence,
        "disposable" => !!payload["disposable"],
        "dns" => !!payload["dns"],
        "whitelist" => !!payload["whitelist"],
        "role" => !!payload["role"],
        "free" => !!payload["free"],
        "alias" => !!payload["alias"],
        "confidence" => integer_or_nil(payload["confidence"]),
        "signals" => Array(payload["signals"]).map(&:to_s).first(20),
        "typo_suggestion" => (SiteSetting.disify_email_protection_typo_suggestions_enabled ? payload["typo_suggestion"].to_s.presence : nil),
      }.compact
    end

    def response_metadata(response, parsed, latency)
      parsed_hash = parsed.is_a?(Hash) ? parsed : {}
      {
        latency_ms: latency,
        rate_limit_limit: integer_or_nil(response["X-RateLimit-Limit"]),
        rate_limit_remaining: integer_or_nil(response["X-RateLimit-Remaining"]),
        retry_after: integer_or_nil(response["Retry-After"] || parsed_hash["retry_after"]),
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
      parsed.is_a?(Hash) ? parsed["error"].to_s.truncate(160).presence : nil
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

    def parse_time(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end

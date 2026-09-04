# frozen_string_literal: true

module ::DisifyEmailProtection
  module Cache
    module_function

    EMAIL_HMAC_PATTERN = /\A[0-9a-f]{64}\z/.freeze
    PERSISTED_RESULT_FIELDS = %w[
      format domain disposable dns whitelist role free alias confidence signals
    ].freeze

    def fetch_email(email)
      hmac = Normalizer.email_hmac(email)
      return nil if hmac.blank?

      fetch("email:#{hmac}")
    end

    def fetch_domain(domain)
      normalized = domain.to_s.downcase
      return nil if normalized.blank?

      fetch("domain:#{normalized}")
    end

    def fetch_risky_domain(domain)
      record = fetch_domain(domain)
      return nil if record.blank?

      result = record["result"] || {}
      risky = result["dns"] == false || result["disposable"] == true
      risky ? record : nil
    end

    def write_email(email, result)
      hmac = Normalizer.email_hmac(email)
      domain = Normalizer.domain(email)
      return if hmac.blank? || domain.blank?

      write_email_fingerprint(email_hmac: hmac, email_domain: domain, result: result)
    end

    def write_email_fingerprint(email_hmac:, email_domain:, result:)
      hmac = email_hmac.to_s.downcase
      domain = email_domain.to_s.downcase
      return nil unless EMAIL_HMAC_PATTERN.match?(hmac)
      return nil unless PolicyExceptions.valid_domain?(domain)

      ttl = SiteSetting.disify_email_protection_email_hmac_cache_ttl_minutes.to_i.minutes
      persist("email:#{hmac}", "email", domain, persistable_result(result), ttl)
    end

    def write_domain(domain, result)
      normalized = domain.to_s.downcase
      return if normalized.blank?

      ttl = SiteSetting.disify_email_protection_domain_cache_ttl_hours.to_i.hours
      stable =
        persistable_result(result).slice(
          "format",
          "domain",
          "disposable",
          "dns",
          "whitelist",
          "free",
          "confidence",
          "signals",
        )
      persist("domain:#{normalized}", "domain", normalized, stable, ttl)
    end

    # Only provider fields that cannot contain a full email address may be persisted.
    # `typo_suggestion` remains available in the immediate in-memory/admin result but
    # is deliberately excluded from plugin tables.
    def persistable_result(result)
      result.to_h.deep_stringify_keys.slice(*PERSISTED_RESULT_FIELDS)
    end

    def fetch(cache_key)
      row = EmailCheck.where(cache_key: cache_key).where("expires_at > ?", Time.zone.now).first
      return nil if row.blank?

      result = row.result.to_h.deep_stringify_keys
      result = persistable_result(result) if row.check_type == "email"
      { "result" => result, "checked_at" => row.checked_at, "source" => "cache" }
    rescue ActiveRecord::StatementInvalid
      nil
    end

    def persist(cache_key, check_type, domain, result, ttl)
      attempts = 0
      begin
        now = Time.zone.now
        row = EmailCheck.find_or_initialize_by(cache_key: cache_key)
        row.check_type = check_type
        row.email_domain = domain
        row.result = result
        row.checked_at = now
        row.expires_at = now + ttl
        row.save!
      rescue ActiveRecord::RecordNotUnique
        attempts += 1
        retry if attempts <= 2
        Rails.logger.warn("[disify_email_protection] cache write abandoned after uniqueness race")
        nil
      end
    rescue StandardError => e
      Rails.logger.warn("[disify_email_protection] cache write failed class=#{e.class}")
      nil
    end
  end
end

# frozen_string_literal: true

module ::DisifyEmailProtection
  module Cache
    module_function

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

      ttl = SiteSetting.disify_email_protection_email_hmac_cache_ttl_minutes.to_i.minutes
      persist("email:#{hmac}", "email", domain, result, ttl)
    end

    def write_domain(domain, result)
      normalized = domain.to_s.downcase
      return if normalized.blank?

      ttl = SiteSetting.disify_email_protection_domain_cache_ttl_hours.to_i.hours
      stable = result.slice("format", "domain", "disposable", "dns", "whitelist", "free", "confidence", "signals")
      persist("domain:#{normalized}", "domain", normalized, stable, ttl)
    end

    def fetch(cache_key)
      row = EmailCheck.where(cache_key: cache_key).where("expires_at > ?", Time.zone.now).first
      return nil if row.blank?

      { "result" => row.result.deep_stringify_keys, "checked_at" => row.checked_at, "source" => "cache" }
    rescue ActiveRecord::StatementInvalid
      nil
    end

    def persist(cache_key, check_type, domain, result, ttl)
      now = Time.zone.now
      row = EmailCheck.find_or_initialize_by(cache_key: cache_key)
      row.check_type = check_type
      row.email_domain = domain
      row.result = result
      row.checked_at = now
      row.expires_at = now + ttl
      row.save!
    rescue ActiveRecord::RecordNotUnique
      retry
    rescue StandardError => e
      Rails.logger.warn("[disify_email_protection] cache write failed class=#{e.class}")
    end
  end
end

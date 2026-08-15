# frozen_string_literal: true

require "openssl"

module ::DisifyEmailProtection
  module Normalizer
    module_function

    def email(value)
      value.to_s.strip.downcase.presence
    end

    def domain(value)
      normalized = email(value)
      return nil if normalized.blank?

      local, host = normalized.split("@", 2)
      return nil if local.blank? || host.blank?

      host
    end

    def email_hmac(value)
      normalized = email(value)
      return nil if normalized.blank?

      OpenSSL::HMAC.hexdigest("SHA256", hmac_secret, normalized)
    end

    def hmac_secret
      Rails.application.secret_key_base.to_s
    end

    def trusted_alias_domain?(host)
      TRUSTED_ALIAS_DOMAINS.include?(host.to_s.downcase)
    end
  end
end

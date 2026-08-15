# frozen_string_literal: true

module ::DisifyEmailProtection
  module PolicyExceptions
    module_function

    def decision_for(email)
      domain = Normalizer.domain(email)
      hmac = Normalizer.email_hmac(email)
      return nil if domain.blank? || hmac.blank?

      records = PolicyException.effective.where(
        "(kind IN ('allow_domain','block_domain') AND lower(value) = ?) OR " \
        "(kind IN ('allow_email_hmac','block_email_hmac') AND value = ?)",
        domain.downcase,
        hmac,
      ).order(id: :desc)

      # Explicit address-level exceptions are more specific than domain rules.
      email_records, domain_records = records.partition { |record| record.kind.end_with?("email_hmac") }
      (email_records + domain_records).each do |record|
        return "bypass" if %w[allow_domain allow_email_hmac].include?(record.kind)
        return "block" if %w[block_domain block_email_hmac].include?(record.kind)
      end

      nil
    end

    def create!(kind:, value:, actor:, reason: nil, expires_at: nil)
      normalized = normalize_value(kind, value)
      raise Discourse::InvalidParameters.new(:value) if normalized.blank?

      PolicyException.create!(
        kind: kind,
        value: normalized,
        reason: reason.to_s.truncate(500).presence,
        created_by_id: actor&.id,
        expires_at: expires_at,
        active: true,
      )
    end

    def create_for_email!(action:, email:, actor:, reason: nil, expires_at: nil)
      normalized = Normalizer.email(email)
      raise Discourse::InvalidParameters.new(:email) unless EmailAddressValidator.valid_value?(normalized)

      kind = action.to_s == "allow" ? "allow_email_hmac" : "block_email_hmac"
      create!(
        kind: kind,
        value: Normalizer.email_hmac(normalized),
        actor: actor,
        reason: reason,
        expires_at: expires_at,
      )
    end

    def normalize_value(kind, value)
      case kind.to_s
      when "allow_domain", "block_domain"
        domain = value.to_s.strip.downcase.sub(/\A@/, "")
        return nil unless valid_domain?(domain)

        domain
      when "allow_email_hmac", "block_email_hmac"
        value.to_s.strip.downcase.match?(/\A[0-9a-f]{64}\z/) ? value.to_s.strip.downcase : nil
      end
    end

    def valid_domain?(domain)
      return false if domain.blank? || domain.length > 255
      return false if domain.include?("@") || domain.include?("/") || domain.include?(" ")

      domain.match?(/\A(?=.{1,255}\z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/i)
    end
  end
end

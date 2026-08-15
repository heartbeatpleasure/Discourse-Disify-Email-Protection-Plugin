# frozen_string_literal: true

module Jobs
  class DisifyEmailProtectionCleanup < ::Jobs::Scheduled
    every 1.day

    def execute(_args)
      now = Time.zone.now
      ::DisifyEmailProtection::EmailCheck.where("expires_at < ?", now - 30.days).delete_all
      ::DisifyEmailProtection::EmailEvent.where(
        "occurred_at < ?",
        SiteSetting.disify_email_protection_event_retention_days.to_i.days.ago,
      ).delete_all
      review_cutoff = SiteSetting.disify_email_protection_event_retention_days.to_i.days.ago
      ::DisifyEmailProtection::ReviewItem.pending.where(
        "created_at < ?",
        review_cutoff,
      ).update_all(state: "expired", resolved_at: now, updated_at: now)
      ::DisifyEmailProtection::ReviewItem.where.not(state: "pending").where(
        "updated_at < ?",
        review_cutoff,
      ).delete_all
      ::DisifyEmailProtection::DailyStat.where(
        "stat_date < ?",
        Date.current - SiteSetting.disify_email_protection_stats_retention_days.to_i.days,
      ).delete_all
      ::DisifyEmailProtection::PolicyException.where(active: true).where(
        "expires_at IS NOT NULL AND expires_at < ?",
        now,
      ).update_all(active: false, updated_at: now)
    end
  end
end

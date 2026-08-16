# frozen_string_literal: true

module Jobs
  class DisifyEmailProtectionCleanup < ::Jobs::Scheduled
    every 1.day

    BATCH_SIZE = 1_000

    def execute(_args)
      now = Time.zone.now
      review_cutoff = SiteSetting.disify_email_protection_event_retention_days.to_i.days.ago

      delete_in_batches(::DisifyEmailProtection::EmailCheck.where("expires_at < ?", now - 30.days))
      delete_in_batches(
        ::DisifyEmailProtection::EmailEvent.where(
          "occurred_at < ?",
          SiteSetting.disify_email_protection_event_retention_days.to_i.days.ago,
        ),
      )
      update_in_batches(
        ::DisifyEmailProtection::ReviewItem.pending.where("created_at < ?", review_cutoff),
        state: "expired",
        resolved_at: now,
        updated_at: now,
      )
      delete_in_batches(
        ::DisifyEmailProtection::ReviewItem.where.not(state: "pending").where("updated_at < ?", review_cutoff),
      )
      delete_in_batches(
        ::DisifyEmailProtection::DailyStat.where(
          "stat_date < ?",
          Date.current - SiteSetting.disify_email_protection_stats_retention_days.to_i.days,
        ),
      )
      update_in_batches(
        ::DisifyEmailProtection::PolicyException.where(active: true).where(
          "expires_at IS NOT NULL AND expires_at < ?",
          now,
        ),
        active: false,
        updated_at: now,
      )
    end

    private

    def delete_in_batches(scope)
      scope.in_batches(of: BATCH_SIZE).delete_all
    end

    def update_in_batches(scope, attributes)
      scope.in_batches(of: BATCH_SIZE).update_all(attributes)
    end
  end
end

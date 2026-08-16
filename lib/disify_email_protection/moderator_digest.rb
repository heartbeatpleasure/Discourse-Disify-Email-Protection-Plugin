# frozen_string_literal: true

module ::DisifyEmailProtection
  module ModeratorDigest
    module_function

    LAST_PERIOD_END_KEY = "activity_digest_last_period_end"
    LAST_SENT_KEY = "activity_digest_last_sent"
    LEGACY_LAST_SENT_KEY = "moderator_digest_last_sent"
    MUTEX_KEY = "disify-email-protection-activity-digest"
    RECIPIENT_GROUPS = {
      "admins" => :admins,
      "staff" => :staff,
    }.freeze
    FREQUENCIES = %w[daily weekly monthly].freeze
    WEEKDAYS = {
      "monday" => 1,
      "tuesday" => 2,
      "wednesday" => 3,
      "thursday" => 4,
      "friday" => 5,
      "saturday" => 6,
      "sunday" => 7,
    }.freeze

    def send_if_needed!(now: Time.zone.now)
      return false unless SiteSetting.disify_email_protection_enabled
      return false unless SiteSetting.disify_email_protection_activity_digest_enabled

      period_end = scheduled_period_end(now)
      return false if period_processed?(period_end)

      DistributedMutex.synchronize(MUTEX_KEY, validity: 30) do
        period_end = scheduled_period_end(now)

        # A newly enabled digest starts with the next scheduled period instead of
        # immediately backfilling historical activity from before it was enabled.
        if last_processed_time.blank?
          PluginStore.set(STORE_NAMESPACE, LAST_PERIOD_END_KEY, period_end.iso8601)
          next false
        end

        next false if period_processed?(period_end)

        period_start = summary_period_start(period_end)
        summary = summary_for(period_start, period_end)
        sent = false

        if meaningful_activity?(summary)
          group = recipient_group
          next false if group.blank? || !group.human_users.exists?

          PostCreator.create!(
            Discourse.system_user,
            target_group_names: [group.name],
            archetype: Archetype.private_message,
            title: I18n.t("disify_email_protection.activity_digest.title"),
            raw: I18n.t(
              "disify_email_protection.activity_digest.body",
              period: period_label(period_start, period_end),
              monitored: summary[:monitored],
              reviewed: summary[:reviewed],
              blocked: summary[:blocked],
              fail_open: summary[:fail_open],
              failures: summary[:failures],
              new_reviews: summary[:new_reviews],
              pending: summary[:pending],
              health: summary[:health],
            ),
          )

          PluginStore.set(STORE_NAMESPACE, LAST_SENT_KEY, Time.zone.now.iso8601)
          sent = true
        end

        # Mark the scheduled period as processed even when it contained no meaningful
        # activity. This prevents the 15-minute scheduler from repeatedly evaluating
        # the same period, while a failed PM creation remains retryable.
        PluginStore.set(STORE_NAMESPACE, LAST_PERIOD_END_KEY, period_end.iso8601)
        sent
      end
    rescue StandardError => e
      Rails.logger.warn("[disify_email_protection] activity digest failed class=#{e.class}")
      false
    end

    def summary_for(period_start, period_end)
      events = EmailEvent.where(occurred_at: period_start...period_end)
      decisions = events.group(:decision).count
      statuses = events.group(:disify_status).count

      {
        monitored: decisions["monitor"].to_i,
        reviewed: decisions["review"].to_i,
        blocked: decisions["block"].to_i,
        fail_open: decisions["fail_open"].to_i,
        failures: statuses["unavailable"].to_i,
        new_reviews: ReviewItem.where(created_at: period_start...period_end).count,
        pending: ReviewItem.pending.count,
        health: Health.payload[:overall].to_s.humanize,
      }
    end

    def meaningful_activity?(summary)
      %i[monitored reviewed blocked fail_open failures new_reviews].sum { |key| summary[key].to_i }.positive?
    end

    def period_processed?(period_end)
      last_end = last_processed_time
      last_end.present? && last_end >= period_end
    end

    def summary_period_start(period_end)
      previous_end = previous_period_end(period_end)
      last_end = last_processed_time

      if last_end.present? && last_end > previous_end && last_end < period_end
        last_end
      else
        previous_end
      end
    end

    def last_processed_time
      parse_time(PluginStore.get(STORE_NAMESPACE, LAST_PERIOD_END_KEY)) ||
        parse_time(PluginStore.get(STORE_NAMESPACE, LEGACY_LAST_SENT_KEY))
    end

    def scheduled_period_end(now)
      now = now.utc
      hour, minute = send_time_parts

      case frequency
      when "daily"
        candidate = Time.utc(now.year, now.month, now.day, hour, minute)
        candidate -= 1.day if candidate > now
        candidate
      when "monthly"
        day = day_of_month
        candidate = Time.utc(now.year, now.month, day, hour, minute)
        if candidate > now
          previous_month = now.to_date.prev_month
          candidate = Time.utc(previous_month.year, previous_month.month, day, hour, minute)
        end
        candidate
      else
        target_cwday = WEEKDAYS.fetch(weekday, 1)
        date = now.to_date - ((now.to_date.cwday - target_cwday) % 7).days
        candidate = Time.utc(date.year, date.month, date.day, hour, minute)
        candidate -= 7.days if candidate > now
        candidate
      end
    end

    def previous_period_end(period_end)
      case frequency
      when "daily"
        period_end - 1.day
      when "monthly"
        previous_month = period_end.to_date.prev_month
        Time.utc(
          previous_month.year,
          previous_month.month,
          day_of_month,
          period_end.hour,
          period_end.min,
        )
      else
        period_end - 7.days
      end
    end

    def frequency
      value = SiteSetting.disify_email_protection_activity_digest_frequency.to_s
      FREQUENCIES.include?(value) ? value : "weekly"
    end

    def weekday
      value = SiteSetting.disify_email_protection_activity_digest_weekday.to_s
      WEEKDAYS.key?(value) ? value : "monday"
    end

    def day_of_month
      [[SiteSetting.disify_email_protection_activity_digest_day_of_month.to_i, 1].max, 28].min
    end

    def send_time_parts
      value = SiteSetting.disify_email_protection_activity_digest_send_time.to_s
      match = /\A([01]\d|2[0-3]):([0-5]\d)\z/.match(value)
      return [9, 0] if match.blank?

      [match[1].to_i, match[2].to_i]
    end

    def recipient_group
      scope = SiteSetting.disify_email_protection_activity_digest_recipients.to_s
      group_key = RECIPIENT_GROUPS[scope]
      return nil if group_key.blank?

      Group[group_key]
    end

    def period_label(period_start, period_end)
      "#{period_start.utc.strftime('%Y-%m-%d %H:%M')} - #{period_end.utc.strftime('%Y-%m-%d %H:%M')} UTC"
    end

    def parse_time(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)&.utc
    rescue ArgumentError, TypeError
      nil
    end
  end
end

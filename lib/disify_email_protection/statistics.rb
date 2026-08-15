# frozen_string_literal: true

module ::DisifyEmailProtection
  module Statistics
    module_function

    COUNTERS = %i[
      checked allowed monitored reviewed blocked_disposable blocked_no_mx blocked_other
      fail_open api_calls cache_hits bypassed api_errors latency_total_ms latency_samples
    ].freeze

    def increment!(values = {})
      safe = COUNTERS.index_with { |key| [values[key].to_i, 0].max }
      now = Time.zone.now
      params = {
        stat_date: Date.current,
        created_at: now,
        updated_at: now,
      }
      COUNTERS.each { |key| params[key] = safe[key] }

      columns = ["stat_date"] + COUNTERS.map(&:to_s) + %w[created_at updated_at]
      placeholders = columns.map { |column| ":#{column}" }.join(", ")
      updates = COUNTERS.map do |key|
        "#{key} = disify_email_protection_daily_stats.#{key} + EXCLUDED.#{key}"
      end
      updates << "updated_at = EXCLUDED.updated_at"

      DB.exec(<<~SQL, params)
        INSERT INTO disify_email_protection_daily_stats (#{columns.join(', ')})
        VALUES (#{placeholders})
        ON CONFLICT (stat_date) DO UPDATE SET #{updates.join(', ')}
      SQL
    rescue StandardError => e
      Rails.logger.warn("[disify_email_protection] stats update failed class=#{e.class}")
      nil
    end

    def today_payload
      row = DailyStat.find_by(stat_date: Date.current)
      payload_for_row(row)
    rescue ActiveRecord::StatementInvalid
      payload_for_row(nil)
    end

    def period_payload(days)
      days = [[days.to_i, 7].max, 365].min
      start_date = Date.current - (days - 1).days
      rows = DailyStat.where(stat_date: start_date..Date.current).order(:stat_date).to_a
      totals = COUNTERS.index_with { 0 }
      rows.each do |row|
        COUNTERS.each { |key| totals[key] += row.public_send(key).to_i }
      end

      {
        period_days: days,
        start_date: start_date.iso8601,
        end_date: Date.current.iso8601,
        totals: totals.merge(average_latency_ms: average_latency(totals)),
        daily: rows.map { |row| payload_for_row(row) },
      }
    end

    def payload_for_row(row)
      values = COUNTERS.index_with { |key| row&.public_send(key).to_i }
      values.merge(
        stat_date: row&.stat_date&.iso8601 || Date.current.iso8601,
        average_latency_ms: average_latency(values),
      )
    end

    def average_latency(values)
      samples = values[:latency_samples].to_i
      return nil if samples <= 0

      (values[:latency_total_ms].to_f / samples).round(1)
    end
  end
end

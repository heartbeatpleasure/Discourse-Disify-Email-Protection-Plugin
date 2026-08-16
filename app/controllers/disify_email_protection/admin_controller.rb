# frozen_string_literal: true

module ::DisifyEmailProtection
  class AdminController < ::Admin::AdminController
    requires_plugin ::DisifyEmailProtection::PLUGIN_NAME

    before_action :disable_response_caching

    ADMIN_ACTION_RATE_LIMIT = 30

    def overview
      render_json_dump(
        health: Health.payload,
        today: Statistics.today_payload,
        pending_reviews: ReviewItem.pending.count,
        recent_events: EmailEvent.where("occurred_at >= ?", 24.hours.ago).count,
      )
    end

    def health
      render_json_dump(Health.payload)
    end

    def health_test
      rate_limit_admin_action!("health-test", 10)
      render_json_dump(Health.test!)
    end

    def reset_circuit
      rate_limit_admin_action!("reset-circuit", 10)
      CircuitBreaker.reset!
      render_json_dump(success: true, circuit_breaker: CircuitBreaker.state)
    end

    def statistics
      period = params[:period].to_i
      period = 30 unless [7, 30, 90, 365].include?(period)
      render_json_dump(Statistics.period_payload(period))
    end

    def review
      page = [params[:page].to_i, 1].max
      per_page = 50
      scope = ReviewItem.includes(:user, :resolved_by).order(id: :desc)
      scope = scope.where(state: params[:state]) if ReviewItem::STATES.include?(params[:state].to_s)
      total = scope.count
      items = scope.offset((page - 1) * per_page).limit(per_page)

      render_json_dump(
        page: page,
        per_page: per_page,
        total: total,
        items: items.map { |item| serialize_review_item(item) },
      )
    end

    def approve_review
      rate_limit_admin_action!("review-approve")
      item = ReviewItem.find(params[:id].to_i)
      ReviewQueue.approve!(item, current_user)
      UserNoteWriter.record!(
        user: item.user,
        reason: item.reason,
        domain: item.email_domain,
        confidence: item.confidence,
        context: "email risk review approved by staff",
      ) if item.user.present?
      render_json_dump(success: true, item: serialize_review_item(item.reload))
    end

    def reject_review
      rate_limit_admin_action!("review-reject")
      item = ReviewItem.find(params[:id].to_i)
      ReviewQueue.reject!(item, current_user)
      UserNoteWriter.record!(
        user: item.user,
        reason: item.reason,
        domain: item.email_domain,
        confidence: item.confidence,
        context: "email risk review rejected by staff",
      ) if item.user.present?
      render_json_dump(success: true, item: serialize_review_item(item.reload))
    end

    def recheck_review
      rate_limit_admin_action!("review-recheck")
      item = ReviewItem.includes(:user).find(params[:id].to_i)
      raise Discourse::InvalidParameters.new(:review) if item.user.blank? || item.user.email.blank?

      result = Decision.evaluate(
        email: item.user.email,
        user: item.user,
        flow: "review_recheck",
        force_remote: true,
        dry_run: true,
        mode_override: "monitor",
        ignore_exceptions: true,
      )
      render_json_dump(success: true, result: serialize_decision(result))
    end

    def tools
      render_json_dump(
        scan: ExistingUserScan.state,
        scan_estimate: {
          users: User.real.where(staged: false).count,
          configured_batch_size: SiteSetting.disify_email_protection_max_scan_batch_size.to_i,
          configured_mode: SiteSetting.disify_email_protection_manual_scan_full_email_mode.to_s,
        },
        quota: Health.stored_health.slice(
          "rate_limit_limit",
          "rate_limit_remaining",
          "reset_at",
        ),
        exceptions: PolicyException.effective.order(id: :desc).limit(200).map { |item| serialize_exception(item) },
      )
    end

    def scan_status
      render_json_dump(
        scan: ExistingUserScan.state,
        quota: Health.stored_health.slice(
          "rate_limit_limit",
          "rate_limit_remaining",
          "reset_at",
        ),
      )
    end

    def manual_check
      rate_limit_admin_action!("manual-check", 20)
      email = params.require(:email).to_s.strip
      raise Discourse::InvalidParameters.new(:email) unless EmailAddressValidator.valid_value?(email)

      result = Decision.evaluate(
        email: email,
        user: nil,
        flow: "admin_tool",
        force_remote: true,
        dry_run: true,
        mode_override: "monitor",
        ignore_exceptions: true,
      )
      pending_review =
        ReviewItem.pending.where(email_hmac: Normalizer.email_hmac(email)).order(id: :desc).first

      render_json_dump(
        success: true,
        domain: Normalizer.domain(email),
        result: serialize_decision(result),
        pending_review: pending_review && serialize_review_item(pending_review),
      )
    end

    def start_scan
      rate_limit_admin_action!("start-scan", 5)
      render_json_dump(
        success: true,
        scan: ExistingUserScan.start!(
          actor: current_user,
          scan_mode: params[:scan_mode],
          request_id: params[:request_id],
        ),
      )
    end

    def resume_scan
      rate_limit_admin_action!("resume-scan", 5)
      render_json_dump(success: true, scan: ExistingUserScan.resume!(actor: current_user))
    end

    def cancel_scan
      rate_limit_admin_action!("cancel-scan", 5)
      render_json_dump(success: true, scan: ExistingUserScan.cancel!(actor: current_user))
    end

    def create_exception
      rate_limit_admin_action!("create-exception")
      kind = params.require(:kind).to_s
      item =
        case kind
        when "allow_domain", "block_domain"
          PolicyExceptions.create!(
            kind: kind,
            value: params.require(:disify_email_protection_exception_value),
            actor: current_user,
            reason: params[:reason],
          )
        when "allow_email", "block_email"
          PolicyExceptions.create_for_email!(
            action: kind.delete_suffix("_email"),
            email: params.require(:disify_email_protection_exception_value),
            actor: current_user,
            reason: params[:reason],
          )
        else
          raise Discourse::InvalidParameters.new(:kind)
        end

      render_json_dump(success: true, exception: serialize_exception(item))
    end

    def delete_exception
      rate_limit_admin_action!("delete-exception")
      item = PolicyException.find(params[:id].to_i)
      item.update!(active: false)
      render_json_dump(success: true)
    end

    private

    def disable_response_caching
      response.headers["Cache-Control"] = "no-store"
    end

    def rate_limit_admin_action!(suffix, limit = ADMIN_ACTION_RATE_LIMIT)
      RateLimiter.new(
        current_user,
        "disify-email-protection-admin-#{suffix}",
        limit,
        1.minute,
      ).performed!
    end

    def serialize_review_item(item)
      {
        id: item.id,
        state: item.state,
        flow: item.flow,
        reason: item.reason,
        email_domain: item.email_domain,
        confidence: item.confidence,
        signals: item.signals,
        created_at: item.created_at&.iso8601,
        resolved_at: item.resolved_at&.iso8601,
        user: item.user && {
          id: item.user.id,
          username: item.user.username,
        },
        resolved_by: item.resolved_by && {
          id: item.resolved_by.id,
          username: item.resolved_by.username,
        },
      }
    end

    def serialize_decision(result)
      {
        decision: result.decision,
        reason: result.reason,
        confidence: result.confidence,
        signals: result.signals,
        source: result.source,
        status: result.status,
        latency_ms: result.latency_ms,
        payload: result.payload,
      }
    end

    def serialize_exception(item)
      value = if item.kind.end_with?("email_hmac")
        "#{item.value.to_s.first(10)}…"
      else
        item.value
      end
      {
        id: item.id,
        kind: item.kind,
        value: value,
        reason: item.reason,
        expires_at: item.expires_at&.iso8601,
        created_at: item.created_at&.iso8601,
        created_by: item.created_by && {
          id: item.created_by.id,
          username: item.created_by.username,
        },
      }
    end
  end
end

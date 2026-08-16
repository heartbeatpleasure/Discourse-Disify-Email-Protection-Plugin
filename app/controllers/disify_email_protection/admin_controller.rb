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
      StaffAudit.log!(actor: current_user, action: "circuit_reset")
      render_json_dump(success: true, circuit_breaker: CircuitBreaker.state)
    end

    def statistics
      period = params[:period].to_i
      period = 30 unless [7, 30, 90, 365].include?(period)
      render_json_dump(Statistics.period_payload(period))
    end

    def review
      requested_page = positive_integer_value(params[:page]) || 1
      per_page = 50
      state = params[:state].to_s
      if state.present? && !ReviewItem::STATES.include?(state)
        raise Discourse::InvalidParameters.new(:state)
      end

      scope = ReviewItem.includes(:user, :resolved_by).order(id: :desc)
      scope = scope.where(state: state) if state.present?
      total = scope.count
      max_page = [(total.to_f / per_page).ceil, 1].max
      page = [requested_page, max_page].min
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
      item = ReviewItem.find(positive_integer_param!(:id))
      ReviewQueue.approve!(item, current_user)
      StaffAudit.log!(actor: current_user, action: "review_approved", details: { review_id: item.id, resolution: "allow_7_days" })
      UserNoteWriter.record!(
        user: item.user,
        reason: item.reason,
        domain: item.email_domain,
        confidence: item.confidence,
        context: "email risk review approved by staff",
      ) if item.user.present?
      render_json_dump(success: true, item: serialize_review_item(item.reload))
    end

    def approve_review_permanently
      rate_limit_admin_action!("review-approve-permanent")
      item = ReviewItem.find(positive_integer_param!(:id))
      ReviewQueue.approve_permanently!(item, current_user)
      StaffAudit.log!(actor: current_user, action: "review_approved_permanently", details: { review_id: item.id, resolution: "allow_permanent" })
      UserNoteWriter.record!(
        user: item.user,
        reason: item.reason,
        domain: item.email_domain,
        confidence: item.confidence,
        context: "email risk review permanently approved by staff",
      ) if item.user.present?
      render_json_dump(success: true, item: serialize_review_item(item.reload))
    end

    def reject_review
      rate_limit_admin_action!("review-reject")
      item = ReviewItem.find(positive_integer_param!(:id))
      ReviewQueue.reject!(item, current_user)
      StaffAudit.log!(actor: current_user, action: "review_rejected", details: { review_id: item.id, resolution: "block_30_days" })
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
      item = ReviewItem.includes(:user).find(positive_integer_param!(:id))
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
        exceptions: PolicyException.effective.order(id: :desc).limit(200).map { |item| serialize_exception(item) },
      )
    end

    def scan_status
      render_json_dump(
        scan: ExistingUserScan.state,
      )
    end

    def manual_check
      rate_limit_admin_action!("manual-check", 20)
      email = params.require(:email).to_s.strip
      if email.bytesize > 320 || !EmailAddressValidator.valid_value?(email)
        raise Discourse::InvalidParameters.new(:email)
      end

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
      scan = ExistingUserScan.start!(
        actor: current_user,
        scan_mode: params[:scan_mode],
        request_id: params[:request_id],
      )
      StaffAudit.log!(
        actor: current_user,
        action: "scan_started",
        details: { scan_id: scan["scan_id"], scan_mode: scan["mode"], scan_status: scan["status"] },
      )
      render_json_dump(success: true, scan: scan)
    end

    def resume_scan
      rate_limit_admin_action!("resume-scan", 5)
      scan = ExistingUserScan.resume!(actor: current_user)
      StaffAudit.log!(
        actor: current_user,
        action: "scan_resumed",
        details: { scan_id: scan["scan_id"], scan_mode: scan["mode"], scan_status: scan["status"] },
      )
      render_json_dump(success: true, scan: scan)
    end

    def cancel_scan
      rate_limit_admin_action!("cancel-scan", 5)
      scan = ExistingUserScan.cancel!(actor: current_user)
      StaffAudit.log!(
        actor: current_user,
        action: "scan_cancelled",
        details: { scan_id: scan["scan_id"], scan_mode: scan["mode"], scan_status: scan["status"] },
      )
      render_json_dump(success: true, scan: scan)
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

      StaffAudit.log!(
        actor: current_user,
        action: "policy_exception_created",
        details: { exception_id: item.id, exception_kind: item.kind },
      )
      render_json_dump(success: true, exception: serialize_exception(item))
    end

    def delete_exception
      rate_limit_admin_action!("delete-exception")
      item = PolicyException.find(positive_integer_param!(:id))
      item.update!(active: false)
      StaffAudit.log!(
        actor: current_user,
        action: "policy_exception_deleted",
        details: { exception_id: item.id, exception_kind: item.kind },
      )
      render_json_dump(success: true)
    end

    private

    def disable_response_caching
      response.headers["Cache-Control"] = "no-store, private"
      response.headers["Pragma"] = "no-cache"
    end

    def positive_integer_param!(name)
      value = positive_integer_value(params[name])
      raise Discourse::InvalidParameters.new(name) unless value

      value
    end

    def positive_integer_value(value)
      integer = Integer(value, exception: false)
      integer&.positive? ? integer : nil
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
        resolution: item.metadata.to_h["resolution"],
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

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

      scope = ReviewItem.includes({ user: :primary_email }, :resolved_by, :email_remediation).order(id: :desc)
      scope = scope.where(state: state) if state.present?
      total = scope.count
      max_page = [(total.to_f / per_page).ceil, 1].max
      page = [requested_page, max_page].min
      items = scope.offset((page - 1) * per_page).limit(per_page).to_a
      email_change_candidates = review_email_change_candidates(items)

      render_json_dump(
        page: page,
        per_page: per_page,
        total: total,
        bulk_remediation_enabled: SiteSetting.disify_email_protection_bulk_remediation_enabled,
        bulk_candidate_count: bulk_candidate_count(state),
        items: items.map do |item|
          serialize_review_item(
            item,
            recheck_available: review_recheck_email(
              item,
              email_change_candidates: email_change_candidates[item.user_id],
            ).present?,
          )
        end,
      )
    end

    def approve_review
      rate_limit_admin_action!("review-approve")
      item = ReviewItem.find(positive_integer_param!(:id))
      ReviewQueue.approve!(item, current_user)
      resolution = item.reload.metadata.to_h["resolution"]
      StaffAudit.log!(actor: current_user, action: "review_approved", details: { review_id: item.id, resolution: resolution })
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

    def require_email_change
      rate_limit_admin_action!("review-require-change")
      item = ReviewItem.includes(user: :primary_email).find(positive_integer_param!(:id))
      remediation = RemediationManager.require_change!(item, current_user)
      RemediationNotifier.notify_required!(remediation)
      StaffAudit.log!(
        actor: current_user,
        action: "remediation_required",
        details: { review_id: item.id, remediation_id: remediation.id, user_id: remediation.user_id },
      )
      UserNoteWriter.record!(
        user: remediation.user,
        reason: remediation.reason,
        domain: remediation.email_domain,
        confidence: remediation.confidence,
        context: "email change required by staff",
      )
      render_json_dump(success: true, item: serialize_review_item(item.reload))
    end

    def cancel_email_remediation
      rate_limit_admin_action!("review-cancel-remediation")
      item = ReviewItem.includes(:email_remediation).find(positive_integer_param!(:id))
      remediation = item.email_remediation
      raise Discourse::InvalidParameters.new(:remediation) if remediation.blank? || !remediation.active?

      RemediationManager.cancel!(remediation, current_user)
      StaffAudit.log!(
        actor: current_user,
        action: "remediation_cancelled",
        details: { review_id: item.id, remediation_id: remediation.id, user_id: remediation.user_id },
      )
      UserNoteWriter.record!(
        user: remediation.user,
        reason: remediation.reason,
        domain: remediation.email_domain,
        confidence: remediation.confidence,
        context: "email-change requirement cancelled by staff",
      ) if remediation.user.present?
      render_json_dump(success: true, item: serialize_review_item(item.reload))
    end

    def bulk_require_email_change
      rate_limit_admin_action!("review-bulk-require-change", 5)
      raise Discourse::InvalidAccess unless SiteSetting.disify_email_protection_bulk_remediation_enabled

      state = params[:state].to_s
      raise Discourse::InvalidParameters.new(:state) unless %w[pending rejected].include?(state)

      review_ids = RemediationManager.bulk_candidate_ids(state)
      candidate_count = review_ids.length
      Jobs.enqueue(
        :disify_email_protection_bulk_require_change,
        actor_id: current_user.id,
        state: state,
        review_ids: review_ids,
      ) if candidate_count.positive?
      StaffAudit.log!(
        actor: current_user,
        action: "remediation_bulk_started",
        details: { bulk_state: state, candidate_count: candidate_count },
      )
      render_json_dump(success: true, queued: candidate_count.positive?, candidate_count: candidate_count)
    end

    def recheck_review
      rate_limit_admin_action!("review-recheck")
      item = ReviewItem.includes(user: :primary_email).find(positive_integer_param!(:id))
      reviewed_email = review_recheck_email(item)
      raise Discourse::InvalidParameters.new(:review) if reviewed_email.blank?

      result = Decision.evaluate(
        email: reviewed_email,
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
        exceptions: PolicyException.effective.includes(:created_by).order(id: :desc).limit(200).map { |item| serialize_exception(item) },
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

    def serialize_review_item(item, recheck_available: false)
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
        recheck_available: recheck_available,
        existing_user_review: item.flow == "existing_user_scan",
        remediation: serialize_remediation(item.email_remediation),
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

    def serialize_remediation(remediation)
      return nil if remediation.blank?

      {
        id: remediation.id,
        state: remediation.state,
        active: remediation.active,
        required_at: remediation.required_at&.iso8601,
        enforce_at: remediation.enforce_at&.iso8601,
        restricted_at: remediation.restricted_at&.iso8601,
        resolved_at: remediation.resolved_at&.iso8601,
        resolution: remediation.resolution,
      }
    end

    def bulk_candidate_count(state)
      return 0 unless SiteSetting.disify_email_protection_bulk_remediation_enabled
      return 0 unless %w[pending rejected].include?(state.to_s)

      RemediationManager.bulk_candidate_ids(state).length
    end

    def review_email_change_candidates(items)
      user_ids =
        items.filter_map do |item|
          item.user_id if item.flow == "email_change" && item.user_id.present?
        end.uniq
      return {} if user_ids.empty?

      complete_state = EmailChangeRequest.states[:complete]
      EmailChangeRequest
        .where(user_id: user_ids)
        .where.not(change_state: complete_state)
        .order(id: :desc)
        .pluck(:user_id, :new_email)
        .each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(user_id, email), grouped|
          grouped[user_id] << email
        end
    end

    def review_recheck_email(item, email_change_candidates: nil)
      return nil if item.user.blank? || item.email_hmac.blank?

      current_email = item.user.email.to_s
      return current_email if review_hmac_matches?(item.email_hmac, current_email)
      return nil unless item.flow == "email_change"

      candidates =
        if email_change_candidates.nil?
          EmailChangeRequest
            .where(user_id: item.user_id)
            .where.not(change_state: EmailChangeRequest.states[:complete])
            .order(id: :desc)
            .limit(20)
            .pluck(:new_email)
        else
          Array(email_change_candidates)
        end

      candidates.find { |candidate| review_hmac_matches?(item.email_hmac, candidate) }
    end

    def review_hmac_matches?(expected_hmac, email)
      actual_hmac = Normalizer.email_hmac(email)
      return false if expected_hmac.blank? || actual_hmac.blank?
      return false unless expected_hmac.bytesize == actual_hmac.bytesize

      ActiveSupport::SecurityUtils.secure_compare(expected_hmac, actual_hmac)
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

import Controller from "@ember/controller";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { tracked } from "@glimmer/tracking";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import getURL from "discourse/lib/get-url";
import { formatDisifyDate } from "../../lib/disify-date";
import { i18n } from "discourse-i18n";

function humanizeToken(value) {
  const text = value?.toString().trim();
  if (!text) {
    return "—";
  }

  const normalized = text.replace(/_/g, " ");
  return normalized.charAt(0).toUpperCase() + normalized.slice(1);
}

function stateLabel(state) {
  const key = {
    pending: "state_pending",
    approved: "state_approved",
    rejected: "state_rejected",
    expired: "state_expired",
  }[state];

  return key
    ? i18n(`admin.disify_email_protection.review.${key}`)
    : humanizeToken(state);
}

function reasonLabel(reason) {
  const key = {
    disposable: "reason_disposable",
    disposable_low_confidence: "reason_disposable_low_confidence",
    no_mx: "reason_no_mx",
    role: "reason_role",
    policy_block: "reason_policy_block",
  }[reason];

  return key
    ? i18n(`admin.disify_email_protection.review.${key}`)
    : humanizeToken(reason);
}

function flowLabel(flow) {
  const key = {
    signup: "flow_signup",
    email_change: "flow_email_change",
    existing_user_scan: "flow_existing_user_scan",
  }[flow];

  return key
    ? i18n(`admin.disify_email_protection.review.${key}`)
    : humanizeToken(flow);
}

function resolutionLabel(resolution) {
  const key = {
    allow_7_days: "resolution_allow_7_days",
    allow_permanent: "resolution_allow_permanent",
    block_30_days: "resolution_block_30_days",
  }[resolution];

  return key
    ? i18n(`admin.disify_email_protection.review.${key}`)
    : null;
}

export default class AdminPluginsDisifyEmailProtectionReviewController extends Controller {
  @service dialog;
  @service toasts;

  @tracked data;
  @tracked state = "pending";
  @tracked page = 1;
  @tracked isLoading = false;
  @tracked workingId;

  get hasPreviousPage() {
    return this.page > 1;
  }

  get hasNextPage() {
    return Boolean(
      this.data && this.page * this.data.per_page < this.data.total
    );
  }

  get previousPageDisabled() {
    return this.isLoading || !this.hasPreviousPage;
  }

  get nextPageDisabled() {
    return this.isLoading || !this.hasNextPage;
  }

  resetState() {
    this.data = undefined;
    this.state = "pending";
    this.page = 1;
    this.isLoading = false;
    this.workingId = undefined;
  }

  @action
  async loadReview() {
    if (this.isLoading) {
      return;
    }

    this.isLoading = true;
    try {
      const query = new URLSearchParams({
        state: this.state,
        page: String(this.page),
      });
      const data = await ajax(
        `/admin/plugins/disify-email-protection/review.json?${query}`
      );
      this.data = {
        ...data,
        items: (data?.items || []).map((item) => ({
          ...item,
          created_at_display: formatDisifyDate(item.created_at),
          resolved_at_display: formatDisifyDate(item.resolved_at),
          state_label: stateLabel(item.state),
          reason_label: reasonLabel(item.reason),
          flow_label: flowLabel(item.flow),
          resolution_label: resolutionLabel(item.resolution),
          confidence_display:
            item.confidence === null || item.confidence === undefined
              ? "—"
              : `${item.confidence} / 100`,
          signals_display: (Array.isArray(item.signals) ? item.signals : []).map(
            (signal) => ({
              raw: signal,
              label: humanizeToken(signal),
            })
          ),
          user_url: item.user?.username
            ? getURL(`/u/${encodeURIComponent(item.user.username)}`)
            : null,
          resolved_by_url: item.resolved_by?.username
            ? getURL(`/u/${encodeURIComponent(item.resolved_by.username)}`)
            : null,
        })),
      };
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isLoading = false;
    }
  }

  @action
  changeState(event) {
    this.state = event.target.value;
    this.page = 1;
    this.loadReview();
  }

  async perform(item, action, successMessageKey) {
    if (this.workingId) {
      return;
    }

    this.workingId = item.id;
    try {
      await ajax(
        `/admin/plugins/disify-email-protection/review/${item.id}/${action}.json`,
        { type: "POST" }
      );
      await this.loadReview();
      this.toasts.success({ data: { message: i18n(successMessageKey) } });
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.workingId = undefined;
    }
  }

  @action
  approve(item) {
    return this.perform(
      item,
      "approve",
      "admin.disify_email_protection.review.approve_success"
    );
  }

  @action
  approvePermanently(item) {
    if (this.workingId) {
      return;
    }

    this.dialog.confirm({
      title: i18n(
        "admin.disify_email_protection.review.approve_permanent_dialog_title"
      ),
      message: i18n(
        "admin.disify_email_protection.review.approve_permanent_dialog_message"
      ),
      confirmButtonLabel:
        "admin.disify_email_protection.review.approve_permanent_dialog_confirm",
      didConfirm: () =>
        this.perform(
          item,
          "approve-permanent",
          "admin.disify_email_protection.review.approve_permanent_success"
        ),
    });
  }

  @action
  reject(item) {
    return this.perform(
      item,
      "reject",
      "admin.disify_email_protection.review.reject_success"
    );
  }

  @action
  recheck(item) {
    return this.perform(
      item,
      "recheck",
      "admin.disify_email_protection.review.recheck_success"
    );
  }

  @action
  previousPage() {
    if (!this.hasPreviousPage || this.isLoading) {
      return;
    }
    this.page -= 1;
    this.loadReview();
  }

  @action
  nextPage() {
    if (!this.hasNextPage || this.isLoading) {
      return;
    }
    this.page += 1;
    this.loadReview();
  }
}

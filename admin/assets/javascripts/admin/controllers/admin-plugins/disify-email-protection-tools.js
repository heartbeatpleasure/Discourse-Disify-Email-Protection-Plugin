import Controller from "@ember/controller";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { tracked } from "@glimmer/tracking";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import getURL from "discourse/lib/get-url";
import { formatDisifyDate } from "../../lib/disify-date";
import { i18n } from "discourse-i18n";

const SCAN_POLL_INTERVAL_MS = 3000;
const MAX_CONSECUTIVE_SCAN_POLL_FAILURES = 3;
const POLLED_SCAN_STATUSES = new Set(["running", "waiting"]);

function exceptionKindLabel(kind) {
  const key = {
    allow_domain: "exception_kind_allow_domain",
    block_domain: "exception_kind_block_domain",
    allow_email_hmac: "exception_kind_allow_email",
    block_email_hmac: "exception_kind_block_email",
  }[kind];

  return key
    ? i18n(`admin.disify_email_protection.tools.${key}`)
    : kind;
}

export default class AdminPluginsDisifyEmailProtectionToolsController extends Controller {
  @service dialog;
  @service toasts;

  @tracked data;
  @tracked isLoading = false;
  @tracked email = "";
  @tracked checkResult;
  @tracked isChecking = false;
  @tracked scanMode = "domain_only";
  @tracked isScanning = false;
  @tracked isCancellingScan = false;
  @tracked exceptionKind = "allow_domain";
  @tracked exceptionValue = "";
  @tracked exceptionReason = "";
  @tracked isSavingException = false;

  scanPollTimer = null;
  scanPollRequestInFlight = false;
  scanPollFailureCount = 0;
  scanPollingRouteActive = false;
  scanPollingSuspended = false;
  scanPollingGeneration = 0;

  get currentScanStatus() {
    return this.data?.scan?.status || "idle";
  }

  get shouldPollScan() {
    return POLLED_SCAN_STATUSES.has(this.currentScanStatus);
  }

  get showResumeScan() {
    return this.currentScanStatus === "paused";
  }

  get showCancelScan() {
    return ["running", "waiting", "paused"].includes(this.currentScanStatus);
  }

  get scanStatusLabel() {
    switch (this.currentScanStatus) {
      case "idle":
        return i18n("admin.disify_email_protection.tools.scan_state_idle");
      case "running":
        return i18n("admin.disify_email_protection.tools.scan_state_running");
      case "waiting":
        return i18n("admin.disify_email_protection.tools.scan_state_waiting");
      case "paused":
        return i18n("admin.disify_email_protection.tools.scan_state_paused");
      case "completed":
        return i18n("admin.disify_email_protection.tools.scan_state_completed");
      case "cancelled":
        return i18n("admin.disify_email_protection.tools.scan_state_cancelled");
      default:
        return this.currentScanStatus;
    }
  }

  get scanLastErrorLabel() {
    const value = this.data?.scan?.last_error;
    if (!value) {
      return "—";
    }
    if (value === "stale_scan") {
      return i18n("admin.disify_email_protection.tools.scan_error_stale");
    }
    if (value === "circuit_open") {
      return i18n("admin.disify_email_protection.tools.scan_error_circuit_open");
    }
    if (value === "rate_limit_window") {
      return i18n("admin.disify_email_protection.tools.scan_error_rate_limit_window");
    }
    return value;
  }

  get canStartScan() {
    return !["running", "waiting", "paused"].includes(this.currentScanStatus);
  }

  get startScanDisabled() {
    return this.isScanning || this.isCancellingScan || !this.canStartScan;
  }

  get scanStatusMessage() {
    switch (this.currentScanStatus) {
      case "running":
        return i18n("admin.disify_email_protection.tools.scan_status_running");
      case "waiting":
        return i18n("admin.disify_email_protection.tools.scan_status_waiting");
      case "paused":
        return i18n("admin.disify_email_protection.tools.scan_status_paused");
      case "completed":
        return null;
      case "cancelled":
        return i18n("admin.disify_email_protection.tools.scan_status_cancelled");
      default:
        return null;
    }
  }

  resetState() {
    this.deactivateScanPolling();
    this.data = undefined;
    this.isLoading = false;
    this.email = "";
    this.checkResult = undefined;
    this.isChecking = false;
    this.scanMode = "domain_only";
    this.isScanning = false;
    this.isCancellingScan = false;
    this.exceptionKind = "allow_domain";
    this.exceptionValue = "";
    this.exceptionReason = "";
    this.isSavingException = false;
    this.scanPollFailureCount = 0;
    this.scanPollingSuspended = false;
  }

  activateScanPolling() {
    this.scanPollingRouteActive = true;
    this.scanPollingSuspended = false;
    this.scanPollingGeneration += 1;
    this.syncScanPolling();
  }

  deactivateScanPolling() {
    this.scanPollingRouteActive = false;
    this.scanPollingSuspended = false;
    this.scanPollingGeneration += 1;
    this.clearScanPollTimer();
  }

  invalidateScanPolling() {
    this.scanPollingGeneration += 1;
    this.clearScanPollTimer();
  }

  clearScanPollTimer() {
    if (this.scanPollTimer !== null) {
      globalThis.clearTimeout(this.scanPollTimer);
      this.scanPollTimer = null;
    }
  }

  syncScanPolling() {
    if (
      !this.scanPollingRouteActive ||
      this.scanPollingSuspended ||
      !this.shouldPollScan
    ) {
      this.clearScanPollTimer();
      return;
    }

    if (this.scanPollTimer !== null) {
      return;
    }

    this.scanPollTimer = globalThis.setTimeout(() => {
      this.scanPollTimer = null;
      void this.pollScanStatus();
    }, SCAN_POLL_INTERVAL_MS);
  }

  async pollScanStatus() {
    if (
      !this.scanPollingRouteActive ||
      this.scanPollingSuspended ||
      !this.shouldPollScan
    ) {
      this.syncScanPolling();
      return;
    }

    if (this.scanPollRequestInFlight) {
      this.syncScanPolling();
      return;
    }

    const generation = this.scanPollingGeneration;
    this.scanPollRequestInFlight = true;

    try {
      const data = await ajax(
        "/admin/plugins/disify-email-protection/tools/scan/status.json"
      );

      if (
        !this.scanPollingRouteActive ||
        generation !== this.scanPollingGeneration
      ) {
        return;
      }

      this.scanPollFailureCount = 0;
      this.scanPollingSuspended = false;
      this.data = {
        ...this.data,
        scan: data.scan,
      };
    } catch (error) {
      if (
        this.scanPollingRouteActive &&
        generation === this.scanPollingGeneration
      ) {
        this.scanPollFailureCount += 1;

        if (
          this.scanPollFailureCount >= MAX_CONSECUTIVE_SCAN_POLL_FAILURES
        ) {
          this.scanPollingSuspended = true;
          this.clearScanPollTimer();
          popupAjaxError(error);
        }
      }
    } finally {
      this.scanPollRequestInFlight = false;

      if (
        this.scanPollingRouteActive &&
        generation === this.scanPollingGeneration
      ) {
        this.syncScanPolling();
      }
    }
  }

  @action
  async loadTools() {
    this.invalidateScanPolling();
    this.isLoading = true;
    try {
      const data = await ajax("/admin/plugins/disify-email-protection/tools.json");
      this.data = {
        ...data,
        exceptions: (data?.exceptions || []).map((item) => ({
          ...item,
          kind_label: exceptionKindLabel(item.kind),
          expires_at_display: item.expires_at
            ? formatDisifyDate(item.expires_at)
            : i18n("admin.disify_email_protection.tools.exception_never_expires"),
          created_at_display: formatDisifyDate(item.created_at),
          created_by_url: item.created_by?.username
            ? getURL(`/u/${encodeURIComponent(item.created_by.username)}`)
            : null,
        })),
      };
      this.scanMode = this.data?.scan_estimate?.configured_mode || "domain_only";
      this.scanPollFailureCount = 0;
      this.scanPollingSuspended = false;
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isLoading = false;
      this.syncScanPolling();
    }
  }

  @action
  updateEmail(event) {
    this.email = event.target.value;
  }

  @action
  async checkEmail() {
    if (!this.email.trim()) {
      return;
    }
    this.isChecking = true;
    this.checkResult = undefined;
    try {
      this.checkResult = await ajax(
        "/admin/plugins/disify-email-protection/tools/check.json",
        { type: "POST", data: { email: this.email.trim() } }
      );
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isChecking = false;
    }
  }

  @action
  changeScanMode(event) {
    this.scanMode = event.target.value;
  }

  @action
  startScan() {
    if (!this.canStartScan) {
      this.toasts.warning({ data: { message: i18n("admin.disify_email_protection.tools.scan_already_running") } });
      return;
    }

    const userCount = Number(this.data?.scan_estimate?.users || 0);
    const dataNotice =
      this.scanMode === "domain_only"
        ? i18n("admin.disify_email_protection.tools.scan_notice_domain_only")
        : this.scanMode === "trusted_providers"
          ? i18n("admin.disify_email_protection.tools.scan_notice_trusted_providers")
          : i18n("admin.disify_email_protection.tools.scan_notice_all");

    const requestId = this.createScanRequestId();

    this.dialog.confirm({
      title: i18n("admin.disify_email_protection.tools.start_scan_dialog_title"),
      message: i18n("admin.disify_email_protection.tools.start_scan_dialog_message", {
        count: userCount,
        data_notice: dataNotice,
      }),
      confirmButtonLabel: "admin.disify_email_protection.tools.start_scan_dialog_confirm",
      didConfirm: () => this.startScanNow(requestId),
    });
  }

  createScanRequestId() {
    if (globalThis.crypto?.randomUUID) {
      return globalThis.crypto.randomUUID();
    }

    return `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  }

  async startScanNow(requestId) {
    if (this.isScanning) {
      return;
    }

    this.invalidateScanPolling();
    this.isScanning = true;
    try {
      await ajax("/admin/plugins/disify-email-protection/tools/scan.json", {
        type: "POST",
        data: { scan_mode: this.scanMode, request_id: requestId },
      });
      await this.loadTools();
      this.toasts.success({ data: { message: i18n("admin.disify_email_protection.tools.start_scan_success") } });
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isScanning = false;
      this.syncScanPolling();
    }
  }

  @action
  async resumeScan() {
    this.invalidateScanPolling();
    this.isScanning = true;
    try {
      await ajax(
        "/admin/plugins/disify-email-protection/tools/scan/resume.json",
        { type: "POST" }
      );
      await this.loadTools();
      this.toasts.success({ data: { message: i18n("admin.disify_email_protection.tools.resume_scan_success") } });
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isScanning = false;
      this.syncScanPolling();
    }
  }


  @action
  cancelScan() {
    if (!this.showCancelScan || this.isCancellingScan) {
      return;
    }

    this.dialog.confirm({
      title: i18n("admin.disify_email_protection.tools.cancel_scan_dialog_title"),
      message: i18n("admin.disify_email_protection.tools.cancel_scan_dialog_message"),
      confirmButtonLabel: "admin.disify_email_protection.tools.cancel_scan_dialog_confirm",
      didConfirm: () => this.cancelScanNow(),
    });
  }

  async cancelScanNow() {
    this.invalidateScanPolling();
    this.isCancellingScan = true;
    try {
      await ajax(
        "/admin/plugins/disify-email-protection/tools/scan/cancel.json",
        { type: "POST" }
      );
      await this.loadTools();
      this.toasts.success({
        data: {
          message: i18n("admin.disify_email_protection.tools.cancel_scan_success"),
        },
      });
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isCancellingScan = false;
      this.syncScanPolling();
    }
  }

  @action
  changeExceptionKind(event) {
    this.exceptionKind = event.target.value;
  }

  @action
  updateExceptionValue(event) {
    this.exceptionValue = event.target.value;
  }

  @action
  updateExceptionReason(event) {
    this.exceptionReason = event.target.value;
  }

  @action
  async addException() {
    if (!this.exceptionValue.trim()) {
      return;
    }
    this.isSavingException = true;
    try {
      await ajax("/admin/plugins/disify-email-protection/exceptions.json", {
        type: "POST",
        data: {
          kind: this.exceptionKind,
          disify_email_protection_exception_value: this.exceptionValue.trim(),
          reason: this.exceptionReason.trim(),
        },
      });
      this.exceptionValue = "";
      this.exceptionReason = "";
      await this.loadTools();
      this.toasts.success({ data: { message: i18n("admin.disify_email_protection.tools.exception_add_success") } });
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isSavingException = false;
    }
  }

  @action
  async deleteException(item) {
    try {
      await ajax(
        `/admin/plugins/disify-email-protection/exceptions/${item.id}.json`,
        { type: "DELETE" }
      );
      await this.loadTools();
      this.toasts.success({ data: { message: i18n("admin.disify_email_protection.tools.exception_delete_success") } });
    } catch (error) {
      popupAjaxError(error);
    }
  }
}

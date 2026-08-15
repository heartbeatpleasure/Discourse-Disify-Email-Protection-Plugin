import Controller from "@ember/controller";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { tracked } from "@glimmer/tracking";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { formatDisifyDate } from "../../lib/disify-date";
import { i18n } from "discourse-i18n";

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

  get currentScanStatus() {
    return this.data?.scan?.status || "idle";
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
        return i18n("admin.disify_email_protection.tools.scan_status_completed");
      case "cancelled":
        return i18n("admin.disify_email_protection.tools.scan_status_cancelled");
      default:
        return null;
    }
  }

  resetState() {
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
  }

  @action
  async loadTools() {
    this.isLoading = true;
    try {
      const data = await ajax("/admin/plugins/disify-email-protection/tools.json");
      this.data = {
        ...data,
        exceptions: (data?.exceptions || []).map((item) => ({
          ...item,
          expires_at_display: formatDisifyDate(item.expires_at),
        })),
      };
      this.scanMode = this.data?.scan_estimate?.configured_mode || "domain_only";
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isLoading = false;
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

    this.dialog.confirm({
      title: i18n("admin.disify_email_protection.tools.start_scan_dialog_title"),
      message: i18n("admin.disify_email_protection.tools.start_scan_dialog_message", {
        count: userCount,
        data_notice: dataNotice,
      }),
      confirmButtonLabel: i18n("admin.disify_email_protection.tools.start_scan_dialog_confirm"),
      didConfirm: () => this.startScanNow(),
    });
  }

  async startScanNow() {
    this.isScanning = true;
    try {
      await ajax("/admin/plugins/disify-email-protection/tools/scan.json", {
        type: "POST",
        data: { scan_mode: this.scanMode },
      });
      await this.loadTools();
      this.toasts.success({ data: { message: i18n("admin.disify_email_protection.tools.start_scan_success") } });
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isScanning = false;
    }
  }

  @action
  async resumeScan() {
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
      confirmButtonLabel: i18n("admin.disify_email_protection.tools.cancel_scan_dialog_confirm"),
      didConfirm: () => this.cancelScanNow(),
    });
  }

  async cancelScanNow() {
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

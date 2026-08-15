import Controller from "@ember/controller";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { tracked } from "@glimmer/tracking";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

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
  @tracked exceptionKind = "allow_domain";
  @tracked exceptionValue = "";
  @tracked exceptionReason = "";
  @tracked isSavingException = false;

  resetState() {
    this.data = undefined;
    this.isLoading = false;
    this.email = "";
    this.checkResult = undefined;
    this.isChecking = false;
    this.scanMode = "domain_only";
    this.isScanning = false;
    this.exceptionKind = "allow_domain";
    this.exceptionValue = "";
    this.exceptionReason = "";
    this.isSavingException = false;
  }

  @action
  async loadTools() {
    this.isLoading = true;
    try {
      this.data = await ajax("/admin/plugins/disify-email-protection/tools.json");
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
    const userCount = Number(this.data?.scan_estimate?.users || 0);
    const dataNotice =
      this.scanMode === "domain_only"
        ? "Only email domains will be sent to DISIFY."
        : this.scanMode === "trusted_providers"
          ? "Full email addresses will be sent only for configured alias-sensitive mailbox providers; other users use domain-only checks."
          : "Full email addresses for all scanned users will be sent to DISIFY.";

    this.dialog.confirm({
      title: "Start existing-user scan?",
      message: `The scan covers up to ${userCount} existing users. ${dataNotice} It never suspends or deletes accounts automatically.`,
      confirmButtonLabel: "Start scan",
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
      this.toasts.success({ data: { message: "Existing-user scan started." } });
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
      this.toasts.success({ data: { message: "Existing-user scan resumed." } });
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isScanning = false;
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
      this.toasts.success({ data: { message: "Policy exception added." } });
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
      this.toasts.success({ data: { message: "Policy exception removed." } });
    } catch (error) {
      popupAjaxError(error);
    }
  }
}

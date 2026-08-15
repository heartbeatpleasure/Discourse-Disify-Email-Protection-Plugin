import Controller from "@ember/controller";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { tracked } from "@glimmer/tracking";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { formatDisifyDate } from "../../lib/disify-date";
import { i18n } from "discourse-i18n";

export default class AdminPluginsDisifyEmailProtectionHealthController extends Controller {
  @service toasts;

  @tracked data;
  @tracked isLoading = false;
  @tracked isTesting = false;
  @tracked isResetting = false;

  resetState() {
    this.data = undefined;
    this.isLoading = false;
    this.isTesting = false;
    this.isResetting = false;
  }

  @action
  async loadHealth() {
    this.isLoading = true;
    try {
      const data = await ajax(
        "/admin/plugins/disify-email-protection/health.json"
      );
      this.data = this.withDisplayDates(data);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isLoading = false;
    }
  }

  @action
  async runTest() {
    this.isTesting = true;
    try {
      const data = await ajax(
        "/admin/plugins/disify-email-protection/health/test.json",
        { type: "POST" }
      );
      this.data = this.withDisplayDates(data);
      this.toasts.success({ data: { message: i18n("admin.disify_email_protection.health.test_success") } });
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isTesting = false;
    }
  }

  withDisplayDates(data) {
    if (!data) {
      return data;
    }

    return {
      ...data,
      provider: {
        ...(data.provider || {}),
        last_success_at_display: formatDisifyDate(data.provider?.last_success_at),
        reset_at_display: formatDisifyDate(data.provider?.reset_at),
      },
      circuit_breaker: {
        ...(data.circuit_breaker || {}),
        open_until_display: formatDisifyDate(data.circuit_breaker?.open_until),
      },
    };
  }

  @action
  async resetCircuit() {
    this.isResetting = true;
    try {
      await ajax(
        "/admin/plugins/disify-email-protection/health/reset-circuit.json",
        { type: "POST" }
      );
      await this.loadHealth();
      this.toasts.success({ data: { message: i18n("admin.disify_email_protection.health.reset_success") } });
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isResetting = false;
    }
  }
}

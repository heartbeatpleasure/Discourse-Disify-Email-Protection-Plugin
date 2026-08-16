import Controller from "@ember/controller";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { htmlSafe } from "@ember/template";
import { tracked } from "@glimmer/tracking";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { formatDisifyDate } from "../../lib/disify-date";
import { i18n } from "discourse-i18n";

const HEALTH_INFO_TOPICS = Object.freeze({
  mode: {
    title: "admin.disify_email_protection.health.label_mode",
    body: "admin.disify_email_protection.health.info_mode",
  },
  auth_mode: {
    title: "admin.disify_email_protection.health.label_auth_mode",
    body: "admin.disify_email_protection.health.info_auth_mode",
  },
  fail_open: {
    title: "admin.disify_email_protection.health.label_fail_open",
    body: "admin.disify_email_protection.health.info_fail_open",
  },
  last_check: {
    title: "admin.disify_email_protection.health.label_last_check",
    body: "admin.disify_email_protection.health.info_last_check",
  },
  last_error: {
    title: "admin.disify_email_protection.health.label_last_error",
    body: "admin.disify_email_protection.health.info_last_error",
  },
  last_latency: {
    title: "admin.disify_email_protection.health.label_last_latency",
    body: "admin.disify_email_protection.health.info_last_latency",
  },
  rate_limit: {
    title: "admin.disify_email_protection.health.label_rate_limit",
    body: "admin.disify_email_protection.health.info_rate_limit",
  },
  reset_at: {
    title: "admin.disify_email_protection.health.label_reset_at",
    body: "admin.disify_email_protection.health.info_reset_at",
  },
  raw_email_stored: {
    title: "admin.disify_email_protection.health.label_raw_email_stored",
    body: "admin.disify_email_protection.health.info_raw_email_stored",
  },
  api_key_exposed: {
    title: "admin.disify_email_protection.health.label_api_key_exposed",
    body: "admin.disify_email_protection.health.info_api_key_exposed",
  },
  full_response_stored: {
    title: "admin.disify_email_protection.health.label_full_response_stored",
    body: "admin.disify_email_protection.health.info_full_response_stored",
  },
  hmac_correlation: {
    title: "admin.disify_email_protection.health.label_hmac_correlation",
    body: "admin.disify_email_protection.health.info_hmac_correlation",
  },
});

export default class AdminPluginsDisifyEmailProtectionHealthController extends Controller {
  @service toasts;

  @tracked data;
  @tracked isLoading = false;
  @tracked isTesting = false;
  @tracked isResetting = false;
  @tracked activeInfoKey = "";
  @tracked infoOverlayStyle = htmlSafe("");
  @tracked infoOverlayPlacement = "below";

  infoTriggerElement = null;

  get activeInfo() {
    const topic = HEALTH_INFO_TOPICS[this.activeInfoKey];
    if (!topic) {
      return null;
    }

    return {
      title: i18n(topic.title),
      body: i18n(topic.body),
    };
  }

  get infoOverlayClass() {
    return `dep-page__info-popover is-${this.infoOverlayPlacement}`;
  }

  resetState() {
    this.data = undefined;
    this.isLoading = false;
    this.isTesting = false;
    this.isResetting = false;
    this.activeInfoKey = "";
    this.infoOverlayStyle = htmlSafe("");
    this.infoOverlayPlacement = "below";
    this.infoTriggerElement = null;
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
        last_check_at_display: formatDisifyDate(data.provider?.last_check_at),
        reset_at_display: formatDisifyDate(data.provider?.reset_at),
        last_error_code_display: data.provider?.last_error_code || "—",
        last_latency_ms_display:
          data.provider?.last_latency_ms === null ||
          data.provider?.last_latency_ms === undefined
            ? "—"
            : data.provider.last_latency_ms,
        rate_limit_limit_display:
          data.provider?.rate_limit_limit === null ||
          data.provider?.rate_limit_limit === undefined
            ? "—"
            : i18n(
                "admin.disify_email_protection.health.rate_limit_per_minute",
                { count: data.provider.rate_limit_limit }
              ),
      },
      circuit_breaker: {
        ...(data.circuit_breaker || {}),
        open_until_display: formatDisifyDate(data.circuit_breaker?.open_until),
      },
    };
  }

  @action
  toggleInfo(key, event) {
    event?.preventDefault?.();
    event?.stopPropagation?.();

    if (!HEALTH_INFO_TOPICS[key]) {
      return;
    }

    if (this.activeInfoKey === key) {
      this.closeInfo();
      return;
    }

    const trigger = event?.currentTarget;
    const rect = trigger?.getBoundingClientRect?.();
    if (!rect || typeof window === "undefined") {
      return;
    }

    const margin = 12;
    const gap = 8;
    const width = Math.min(390, Math.max(0, window.innerWidth - margin * 2));
    const idealLeft = rect.left + rect.width / 2 - width / 2;
    const left = Math.max(
      margin,
      Math.min(idealLeft, window.innerWidth - width - margin)
    );
    const spaceBelow = Math.max(0, window.innerHeight - rect.bottom - margin - gap);
    const spaceAbove = Math.max(0, rect.top - margin - gap);
    const availableSide = Math.max(spaceBelow, spaceAbove);
    const useViewportPanel = availableSide < 140;
    const placeAbove = !useViewportPanel && spaceBelow < 220 && spaceAbove > spaceBelow;
    const availableHeight = useViewportPanel
      ? Math.max(0, window.innerHeight - margin * 2)
      : placeAbove
        ? spaceAbove
        : spaceBelow;
    const top = useViewportPanel
      ? margin
      : placeAbove
        ? rect.top - gap
        : rect.bottom + gap;
    const transform = placeAbove ? "translateY(-100%)" : "none";

    this.infoOverlayPlacement = useViewportPanel
      ? "viewport"
      : placeAbove
        ? "above"
        : "below";
    this.infoOverlayStyle = htmlSafe(
      `left:${Math.round(left)}px;top:${Math.round(top)}px;width:${Math.round(
        width
      )}px;max-height:${Math.floor(availableHeight)}px;transform:${transform};`
    );
    this.infoTriggerElement = trigger;
    this.activeInfoKey = key;

    requestAnimationFrame(() => {
      document.getElementById("dep-health-info-overlay")?.focus();
    });
  }

  @action
  handleInfoTriggerKeydown(key, event) {
    if (!["Enter", " ", "Spacebar"].includes(event?.key)) {
      return;
    }

    event.preventDefault();
    this.toggleInfo(key, event);
  }

  @action
  closeInfo() {
    const trigger = this.infoTriggerElement;
    this.activeInfoKey = "";
    this.infoOverlayStyle = htmlSafe("");
    this.infoTriggerElement = null;

    requestAnimationFrame(() => {
      if (trigger?.isConnected) {
        trigger.focus();
      }
    });
  }

  @action
  handleInfoKeydown(event) {
    if (event?.key === "Escape") {
      event.preventDefault();
      this.closeInfo();
    }
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

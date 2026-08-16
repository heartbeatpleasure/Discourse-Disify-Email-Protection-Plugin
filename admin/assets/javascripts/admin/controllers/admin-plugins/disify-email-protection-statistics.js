import Controller from "@ember/controller";
import { action } from "@ember/object";
import { htmlSafe } from "@ember/template";
import { tracked } from "@glimmer/tracking";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { formatDisifyDateOnly } from "../../lib/disify-date";
import { i18n } from "discourse-i18n";

const STATISTICS_INFO_TOPICS = Object.freeze({
  checks: {
    title: "admin.disify_email_protection.statistics.metric_checks",
    body: "admin.disify_email_protection.statistics.info_checks",
  },
  monitored: {
    title: "admin.disify_email_protection.statistics.metric_monitored",
    body: "admin.disify_email_protection.statistics.info_monitored",
  },
  reviewed: {
    title: "admin.disify_email_protection.statistics.metric_reviewed",
    body: "admin.disify_email_protection.statistics.info_reviewed",
  },
  fail_open: {
    title: "admin.disify_email_protection.statistics.metric_fail_open",
    body: "admin.disify_email_protection.statistics.info_fail_open",
  },
  api_calls: {
    title: "admin.disify_email_protection.statistics.metric_api_calls",
    body: "admin.disify_email_protection.statistics.info_api_calls",
  },
  cache_hits: {
    title: "admin.disify_email_protection.statistics.metric_cache_hits",
    body: "admin.disify_email_protection.statistics.info_cache_hits",
  },
});

export default class AdminPluginsDisifyEmailProtectionStatisticsController extends Controller {
  @tracked data;
  @tracked period = "30";
  @tracked isLoading = false;
  @tracked activeInfoKey = "";
  @tracked infoOverlayStyle = htmlSafe("");
  @tracked infoOverlayPlacement = "below";

  infoTriggerElement = null;

  get activeInfo() {
    const topic = STATISTICS_INFO_TOPICS[this.activeInfoKey];
    if (!topic) {
      return null;
    }

    return {
      title: i18n(topic.title),
      body: i18n(topic.body),
    };
  }

  get infoOverlayClass() {
    return `dep-stats__info-popover is-${this.infoOverlayPlacement}`;
  }

  resetState() {
    this.data = undefined;
    this.period = "30";
    this.isLoading = false;
    this.activeInfoKey = "";
    this.infoOverlayStyle = htmlSafe("");
    this.infoOverlayPlacement = "below";
    this.infoTriggerElement = null;
  }

  @action
  async loadStatistics() {
    if (this.isLoading) {
      return;
    }

    this.isLoading = true;
    try {
      const data = await ajax(
        `/admin/plugins/disify-email-protection/statistics.json?period=${this.period}`
      );
      this.data = {
        ...data,
        daily: (data?.daily || []).map((day) => ({
          ...day,
          stat_date_display: formatDisifyDateOnly(day.stat_date),
          average_latency_display:
            day.average_latency_ms === null ||
            day.average_latency_ms === undefined
              ? "—"
              : `${day.average_latency_ms} ms`,
        })),
      };
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isLoading = false;
    }
  }

  @action
  changePeriod(event) {
    this.period = event.target.value;
    void this.loadStatistics();
  }

  @action
  toggleInfo(key, event) {
    event?.preventDefault?.();
    event?.stopPropagation?.();

    if (!STATISTICS_INFO_TOPICS[key]) {
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
    const spaceBelow = Math.max(
      0,
      window.innerHeight - rect.bottom - margin - gap
    );
    const spaceAbove = Math.max(0, rect.top - margin - gap);
    const availableSide = Math.max(spaceBelow, spaceAbove);
    const useViewportPanel = availableSide < 140;
    const placeAbove =
      !useViewportPanel && spaceBelow < 220 && spaceAbove > spaceBelow;
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
      document.getElementById("dep-stats-info-overlay")?.focus();
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
}

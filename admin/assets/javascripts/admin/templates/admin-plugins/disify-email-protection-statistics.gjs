import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import RouteTemplate from "ember-route-template";
import getURL from "discourse/lib/get-url";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

const overviewUrl = getURL("/admin/plugins/disify-email-protection");

export default RouteTemplate(
  <template>
    <style>
      .dep-stats {
        --dep-surface: var(--secondary);
        --dep-surface-alt: var(--primary-very-low);
        --dep-border: var(--primary-low);
        --dep-muted: var(--primary-medium);
        display: flex;
        flex-direction: column;
        gap: 1rem;
      }
      .dep-stats h1, .dep-stats h2, .dep-stats h3, .dep-stats h4, .dep-stats p { margin: 0; }
      .dep-stats__hero, .dep-stats__panel {
        min-width: 0;
        padding: 1.2rem 1.35rem;
        border: 1px solid var(--dep-border);
        border-radius: 18px;
        background: var(--dep-surface);
        box-shadow: 0 1px 2px rgb(0 0 0 / 3%);
      }
      .dep-stats__hero {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: 1rem;
      }
      .dep-stats__copy {
        display: flex;
        min-width: 0;
        flex: 1 1 auto;
        flex-direction: column;
        gap: .35rem;
      }
      .dep-stats__muted { color: var(--dep-muted); }
      .dep-stats__actions {
        display: flex;
        flex: 0 0 auto;
        flex-wrap: nowrap;
        align-items: center;
        justify-content: flex-end;
        gap: .5rem;
        margin-left: auto;
      }
      .dep-stats__actions .btn { white-space: nowrap; }
      .dep-stats__toolbar {
        display: flex;
        justify-content: space-between;
        align-items: flex-end;
        gap: 1rem;
      }
      .dep-stats__control {
        width: min(18rem, 100%);
        min-height: 42px;
        padding: 0 .85rem;
        border: 1px solid var(--dep-border);
        border-radius: 12px;
        background: var(--dep-surface-alt);
        box-sizing: border-box;
      }
      .dep-stats__grid {
        display: grid;
        grid-template-columns: repeat(4, minmax(0, 1fr));
        gap: .75rem;
      }
      .dep-stats__metric {
        min-width: 0;
        padding: .8rem;
        border-radius: 12px;
        background: var(--dep-surface-alt);
      }
      .dep-stats__label-row {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: .45rem;
        min-width: 0;
      }
      .dep-stats__label {
        min-width: 0;
        color: var(--dep-muted);
        font-size: var(--font-down-1);
        font-weight: 700;
      }
      .dep-stats__value {
        margin-top: .2rem;
        font-size: var(--font-up-2);
        font-weight: 700;
        overflow-wrap: anywhere;
      }
      .dep-stats__daily-list {
        display: grid;
        gap: .8rem;
        margin-top: .9rem;
      }
      .dep-stats__daily-card {
        min-width: 0;
        padding: .9rem;
        border: 1px solid var(--dep-border);
        border-radius: 14px;
        background: var(--dep-surface-alt);
      }
      .dep-stats__daily-header {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: 1rem;
        padding-bottom: .7rem;
        border-bottom: 1px solid var(--dep-border);
      }
      .dep-stats__daily-header h3 { font-size: var(--font-up-1); }
      .dep-stats__daily-groups {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: .65rem;
        margin-top: .7rem;
      }
      .dep-stats__daily-group {
        min-width: 0;
        padding: .7rem;
        border-radius: 11px;
        background: var(--secondary);
      }
      .dep-stats__daily-group h4 {
        margin-bottom: .55rem;
        color: var(--dep-muted);
        font-size: var(--font-down-1);
        font-weight: 700;
      }
      .dep-stats__daily-metrics {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: .5rem .75rem;
      }
      .dep-stats__daily-metric { min-width: 0; }
      .dep-stats__daily-metric-label {
        color: var(--dep-muted);
        font-size: var(--font-down-2);
      }
      .dep-stats__daily-metric-value {
        margin-top: .08rem;
        font-weight: 700;
        overflow-wrap: anywhere;
      }
      .dep-stats__info {
        position: relative;
        z-index: 1;
        display: inline-flex;
        flex: 0 0 auto;
        align-items: center;
        justify-content: center;
        width: 1.35rem;
        height: 1.35rem;
        min-width: 1.35rem;
        min-height: 1.35rem;
        box-sizing: border-box;
        padding: 0;
        margin: 0;
        border: 1px solid var(--primary-low-mid, currentColor);
        border-radius: 999px;
        background: var(--primary-very-low, transparent);
        color: var(--primary-high, currentColor);
        font-family: Arial, sans-serif;
        font-size: var(--font-down-1, .875rem);
        font-weight: 700;
        font-style: normal;
        line-height: 1;
        cursor: help;
        box-shadow: none;
        user-select: none;
      }
      .dep-stats__info:hover,
      .dep-stats__info:focus-visible,
      .dep-stats__info[aria-expanded="true"] {
        border-color: var(--tertiary, currentColor);
        background: var(--tertiary-low, var(--primary-low));
        color: var(--tertiary, currentColor);
        outline: none;
      }
      .dep-stats__info:focus-visible {
        outline: 2px solid var(--tertiary, currentColor);
        outline-offset: 2px;
      }
      .dep-stats__info-backdrop {
        position: fixed;
        inset: 0;
        z-index: 19998;
        border: 0;
        padding: 0;
        margin: 0;
        background: transparent;
        cursor: default;
      }
      .dep-stats__info-popover {
        position: fixed;
        z-index: 19999;
        display: grid;
        gap: .75rem;
        overflow: auto;
        overscroll-behavior: contain;
        padding: .9rem;
        border: 1px solid var(--primary-low-mid);
        border-radius: 14px;
        background: var(--secondary);
        color: var(--primary);
        box-shadow: 0 14px 42px rgb(0 0 0 / 28%);
      }
      .dep-stats__info-popover-header {
        position: sticky;
        top: -.9rem;
        z-index: 1;
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: .75rem;
        margin: -.9rem -.9rem 0;
        padding: .9rem .9rem .65rem;
        border-bottom: 1px solid var(--primary-low);
        background: var(--secondary);
      }
      .dep-stats__info-popover-header > div {
        display: grid;
        gap: .15rem;
        min-width: 0;
      }
      .dep-stats__info-popover-kicker {
        color: var(--tertiary);
        font-size: var(--font-down-1);
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: .04em;
      }
      .dep-stats__info-popover-close {
        display: grid;
        place-items: center;
        width: 1.8rem;
        height: 1.8rem;
        min-width: 1.8rem;
        padding: 0;
        border: 0;
        border-radius: 8px;
        background: transparent;
        color: var(--primary-high);
        font-size: 1.3rem;
        line-height: 1;
        cursor: pointer;
      }
      .dep-stats__info-popover-close:hover,
      .dep-stats__info-popover-close:focus-visible {
        background: var(--primary-very-low);
        outline: 2px solid var(--tertiary);
        outline-offset: 1px;
      }
      .dep-stats__info-popover-body {
        color: var(--primary-high);
        font-size: var(--font-down-1);
        line-height: 1.5;
      }
      @media (max-width: 1000px) {
        .dep-stats__daily-groups { grid-template-columns: 1fr 1fr; }
      }
      @media (max-width: 900px) {
        .dep-stats__hero { flex-direction: column; }
        .dep-stats__actions { align-self: flex-end; margin-left: 0; }
        .dep-stats__grid { grid-template-columns: repeat(2, 1fr); }
      }
      @media (max-width: 700px) {
        .dep-stats__toolbar { flex-direction: column; align-items: stretch; }
        .dep-stats__control { width: 100%; }
        .dep-stats__grid, .dep-stats__daily-groups { grid-template-columns: 1fr; }
        .dep-stats__daily-header { flex-direction: column; align-items: flex-start; gap: .25rem; }
      }
      @media (max-width: 460px) {
        .dep-stats__daily-metrics { grid-template-columns: 1fr; }
      }
    </style>

    <div class="dep-stats">
      <section class="dep-stats__hero">
        <div class="dep-stats__copy">
          <h1>{{i18n "admin.disify_email_protection.statistics.title"}}</h1>
          <p class="dep-stats__muted">{{i18n "admin.disify_email_protection.statistics.description"}}</p>
        </div>
        <div class="dep-stats__actions">
          <button class="btn" type="button" {{on "click" @controller.loadStatistics}} disabled={{@controller.isLoading}}>{{i18n "admin.disify_email_protection.statistics.refresh"}}</button>
          <a class="btn" href={{overviewUrl}}>{{i18n "admin.disify_email_protection.statistics.back"}}</a>
        </div>
      </section>

      <section class="dep-stats__panel">
        <div class="dep-stats__toolbar">
          <div class="dep-stats__copy">
            <h2>{{i18n "admin.disify_email_protection.statistics.period_title"}}</h2>
            <p class="dep-stats__muted">{{i18n "admin.disify_email_protection.statistics.period_description"}}</p>
          </div>
          <select class="dep-stats__control" value={{@controller.period}} {{on "change" @controller.changePeriod}} aria-label={{i18n "admin.disify_email_protection.statistics.period_label"}} disabled={{@controller.isLoading}}>
            <option value="7">{{i18n "admin.disify_email_protection.statistics.period_7"}}</option>
            <option value="30">{{i18n "admin.disify_email_protection.statistics.period_30"}}</option>
            <option value="90">{{i18n "admin.disify_email_protection.statistics.period_90"}}</option>
            <option value="365">{{i18n "admin.disify_email_protection.statistics.period_365"}}</option>
          </select>
        </div>
      </section>

      {{#if @controller.data}}
        <section class="dep-stats__panel">
          <div class="dep-stats__grid">
            <div class="dep-stats__metric">
              <div class="dep-stats__label-row">
                <div class="dep-stats__label">{{i18n "admin.disify_email_protection.statistics.metric_checks"}}</div>
                <button class="dep-stats__info" type="button" aria-label={{i18n "admin.disify_email_protection.statistics.info_checks"}} aria-expanded={{eq @controller.activeInfoKey "checks"}} aria-controls="dep-stats-info-overlay" {{on "click" (fn @controller.toggleInfo "checks")}} {{on "keydown" (fn @controller.handleInfoTriggerKeydown "checks")}}>i</button>
              </div>
              <div class="dep-stats__value">{{@controller.data.totals.checked}}</div>
            </div>
            <div class="dep-stats__metric"><div class="dep-stats__label">{{i18n "admin.disify_email_protection.statistics.metric_blocked_disposable"}}</div><div class="dep-stats__value">{{@controller.data.totals.blocked_disposable}}</div></div>
            <div class="dep-stats__metric"><div class="dep-stats__label">{{i18n "admin.disify_email_protection.statistics.metric_blocked_no_mx"}}</div><div class="dep-stats__value">{{@controller.data.totals.blocked_no_mx}}</div></div>
            <div class="dep-stats__metric">
              <div class="dep-stats__label-row">
                <div class="dep-stats__label">{{i18n "admin.disify_email_protection.statistics.metric_fail_open"}}</div>
                <button class="dep-stats__info" type="button" aria-label={{i18n "admin.disify_email_protection.statistics.info_fail_open"}} aria-expanded={{eq @controller.activeInfoKey "fail_open"}} aria-controls="dep-stats-info-overlay" {{on "click" (fn @controller.toggleInfo "fail_open")}} {{on "keydown" (fn @controller.handleInfoTriggerKeydown "fail_open")}}>i</button>
              </div>
              <div class="dep-stats__value">{{@controller.data.totals.fail_open}}</div>
            </div>
            <div class="dep-stats__metric">
              <div class="dep-stats__label-row">
                <div class="dep-stats__label">{{i18n "admin.disify_email_protection.statistics.metric_monitored"}}</div>
                <button class="dep-stats__info" type="button" aria-label={{i18n "admin.disify_email_protection.statistics.info_monitored"}} aria-expanded={{eq @controller.activeInfoKey "monitored"}} aria-controls="dep-stats-info-overlay" {{on "click" (fn @controller.toggleInfo "monitored")}} {{on "keydown" (fn @controller.handleInfoTriggerKeydown "monitored")}}>i</button>
              </div>
              <div class="dep-stats__value">{{@controller.data.totals.monitored}}</div>
            </div>
            <div class="dep-stats__metric">
              <div class="dep-stats__label-row">
                <div class="dep-stats__label">{{i18n "admin.disify_email_protection.statistics.metric_reviewed"}}</div>
                <button class="dep-stats__info" type="button" aria-label={{i18n "admin.disify_email_protection.statistics.info_reviewed"}} aria-expanded={{eq @controller.activeInfoKey "reviewed"}} aria-controls="dep-stats-info-overlay" {{on "click" (fn @controller.toggleInfo "reviewed")}} {{on "keydown" (fn @controller.handleInfoTriggerKeydown "reviewed")}}>i</button>
              </div>
              <div class="dep-stats__value">{{@controller.data.totals.reviewed}}</div>
            </div>
            <div class="dep-stats__metric">
              <div class="dep-stats__label-row">
                <div class="dep-stats__label">{{i18n "admin.disify_email_protection.statistics.metric_api_calls"}}</div>
                <button class="dep-stats__info" type="button" aria-label={{i18n "admin.disify_email_protection.statistics.info_api_calls"}} aria-expanded={{eq @controller.activeInfoKey "api_calls"}} aria-controls="dep-stats-info-overlay" {{on "click" (fn @controller.toggleInfo "api_calls")}} {{on "keydown" (fn @controller.handleInfoTriggerKeydown "api_calls")}}>i</button>
              </div>
              <div class="dep-stats__value">{{@controller.data.totals.api_calls}}</div>
            </div>
            <div class="dep-stats__metric">
              <div class="dep-stats__label-row">
                <div class="dep-stats__label">{{i18n "admin.disify_email_protection.statistics.metric_cache_hits"}}</div>
                <button class="dep-stats__info" type="button" aria-label={{i18n "admin.disify_email_protection.statistics.info_cache_hits"}} aria-expanded={{eq @controller.activeInfoKey "cache_hits"}} aria-controls="dep-stats-info-overlay" {{on "click" (fn @controller.toggleInfo "cache_hits")}} {{on "keydown" (fn @controller.handleInfoTriggerKeydown "cache_hits")}}>i</button>
              </div>
              <div class="dep-stats__value">{{@controller.data.totals.cache_hits}}</div>
            </div>
          </div>
        </section>

        <section class="dep-stats__panel">
          <div class="dep-stats__copy">
            <h2>{{i18n "admin.disify_email_protection.statistics.daily_activity"}}</h2>
            <p class="dep-stats__muted">{{i18n "admin.disify_email_protection.statistics.daily_activity_description"}}</p>
          </div>

          {{#if @controller.data.daily.length}}
            <div class="dep-stats__daily-list">
              {{#each @controller.data.daily as |day|}}
                <article class="dep-stats__daily-card">
                  <div class="dep-stats__daily-header">
                    <h3>{{day.stat_date_display}}</h3>
                    <span class="dep-stats__muted">{{i18n "admin.disify_email_protection.statistics.daily_checks_summary" count=day.checked}}</span>
                  </div>

                  <div class="dep-stats__daily-groups">
                    <section class="dep-stats__daily-group">
                      <h4>{{i18n "admin.disify_email_protection.statistics.group_decisions"}}</h4>
                      <div class="dep-stats__daily-metrics">
                        <div class="dep-stats__daily-metric"><div class="dep-stats__daily-metric-label">{{i18n "admin.disify_email_protection.statistics.metric_checks"}}</div><div class="dep-stats__daily-metric-value">{{day.checked}}</div></div>
                        <div class="dep-stats__daily-metric"><div class="dep-stats__daily-metric-label">{{i18n "admin.disify_email_protection.statistics.col_allowed"}}</div><div class="dep-stats__daily-metric-value">{{day.allowed}}</div></div>
                        <div class="dep-stats__daily-metric"><div class="dep-stats__daily-metric-label">{{i18n "admin.disify_email_protection.statistics.metric_monitored"}}</div><div class="dep-stats__daily-metric-value">{{day.monitored}}</div></div>
                        <div class="dep-stats__daily-metric"><div class="dep-stats__daily-metric-label">{{i18n "admin.disify_email_protection.statistics.metric_reviewed"}}</div><div class="dep-stats__daily-metric-value">{{day.reviewed}}</div></div>
                        <div class="dep-stats__daily-metric"><div class="dep-stats__daily-metric-label">{{i18n "admin.disify_email_protection.statistics.metric_bypassed"}}</div><div class="dep-stats__daily-metric-value">{{day.bypassed}}</div></div>
                      </div>
                    </section>

                    <section class="dep-stats__daily-group">
                      <h4>{{i18n "admin.disify_email_protection.statistics.group_blocks"}}</h4>
                      <div class="dep-stats__daily-metrics">
                        <div class="dep-stats__daily-metric"><div class="dep-stats__daily-metric-label">{{i18n "admin.disify_email_protection.statistics.metric_blocked_disposable"}}</div><div class="dep-stats__daily-metric-value">{{day.blocked_disposable}}</div></div>
                        <div class="dep-stats__daily-metric"><div class="dep-stats__daily-metric-label">{{i18n "admin.disify_email_protection.statistics.metric_blocked_no_mx"}}</div><div class="dep-stats__daily-metric-value">{{day.blocked_no_mx}}</div></div>
                        <div class="dep-stats__daily-metric"><div class="dep-stats__daily-metric-label">{{i18n "admin.disify_email_protection.statistics.metric_blocked_other"}}</div><div class="dep-stats__daily-metric-value">{{day.blocked_other}}</div></div>
                        <div class="dep-stats__daily-metric"><div class="dep-stats__daily-metric-label">{{i18n "admin.disify_email_protection.statistics.metric_fail_open"}}</div><div class="dep-stats__daily-metric-value">{{day.fail_open}}</div></div>
                      </div>
                    </section>

                    <section class="dep-stats__daily-group">
                      <h4>{{i18n "admin.disify_email_protection.statistics.group_provider"}}</h4>
                      <div class="dep-stats__daily-metrics">
                        <div class="dep-stats__daily-metric"><div class="dep-stats__daily-metric-label">{{i18n "admin.disify_email_protection.statistics.metric_api_calls"}}</div><div class="dep-stats__daily-metric-value">{{day.api_calls}}</div></div>
                        <div class="dep-stats__daily-metric"><div class="dep-stats__daily-metric-label">{{i18n "admin.disify_email_protection.statistics.metric_cache_hits"}}</div><div class="dep-stats__daily-metric-value">{{day.cache_hits}}</div></div>
                        <div class="dep-stats__daily-metric"><div class="dep-stats__daily-metric-label">{{i18n "admin.disify_email_protection.statistics.metric_api_errors"}}</div><div class="dep-stats__daily-metric-value">{{day.api_errors}}</div></div>
                        <div class="dep-stats__daily-metric"><div class="dep-stats__daily-metric-label">{{i18n "admin.disify_email_protection.statistics.col_average_latency"}}</div><div class="dep-stats__daily-metric-value">{{day.average_latency_display}}</div></div>
                      </div>
                    </section>
                  </div>
                </article>
              {{/each}}
            </div>
          {{else}}
            <p class="dep-stats__muted" style="margin-top:.9rem;">{{i18n "admin.disify_email_protection.statistics.daily_empty"}}</p>
          {{/if}}
        </section>
      {{/if}}

      {{#if @controller.activeInfo}}
        <button class="dep-stats__info-backdrop" type="button" tabindex="-1" aria-label={{i18n "admin.disify_email_protection.statistics.info_close"}} {{on "click" @controller.closeInfo}}></button>
        <aside id="dep-stats-info-overlay" class={{@controller.infoOverlayClass}} style={{@controller.infoOverlayStyle}} role="dialog" aria-modal="false" aria-label={{@controller.activeInfo.title}} tabindex="-1" {{on "keydown" @controller.handleInfoKeydown}}>
          <div class="dep-stats__info-popover-header">
            <div>
              <span class="dep-stats__info-popover-kicker">{{i18n "admin.disify_email_protection.statistics.info_kicker"}}</span>
              <h3>{{@controller.activeInfo.title}}</h3>
            </div>
            <button class="dep-stats__info-popover-close" type="button" aria-label={{i18n "admin.disify_email_protection.statistics.info_close"}} {{on "click" @controller.closeInfo}}>×</button>
          </div>
          <div class="dep-stats__info-popover-body">
            <p>{{@controller.activeInfo.body}}</p>
          </div>
        </aside>
      {{/if}}
    </div>
  </template>
);

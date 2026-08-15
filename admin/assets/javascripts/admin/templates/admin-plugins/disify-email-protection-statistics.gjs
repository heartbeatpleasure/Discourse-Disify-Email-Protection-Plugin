import { on } from "@ember/modifier";
import RouteTemplate from "ember-route-template";
import getURL from "discourse/lib/get-url";
import { i18n } from "discourse-i18n";

const overviewUrl = getURL("/admin/plugins/disify-email-protection");

export default RouteTemplate(
  <template>
    <style>
      .dep-stats { display: grid; gap: 1rem; }
      .dep-stats h1, .dep-stats h2, .dep-stats p { margin: 0; }
      .dep-stats__hero, .dep-stats__panel { padding: 1rem 1.15rem; border: 1px solid var(--primary-low); border-radius: 16px; background: var(--secondary); }
      .dep-stats__hero { display: flex; justify-content: space-between; align-items: flex-start; gap: 1rem; }
      .dep-stats__copy { display: grid; gap: .35rem; }
      .dep-stats__muted { color: var(--primary-medium); }
      .dep-stats__actions { display: flex; gap: .5rem; align-items: center; flex-wrap: wrap; }
      .dep-stats__toolbar { display: flex; justify-content: space-between; align-items: center; gap: .75rem; }
      .dep-stats__control { min-height: 2.75rem; padding: .55rem .75rem; box-sizing: border-box; }
      .dep-stats__grid { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: .75rem; }
      .dep-stats__metric { padding: .8rem; border-radius: 12px; background: var(--primary-very-low); }
      .dep-stats__label { color: var(--primary-medium); font-size: var(--font-down-1); font-weight: 700; }
      .dep-stats__value { margin-top: .2rem; font-size: var(--font-up-2); font-weight: 700; }
      .dep-stats__table-wrap { overflow-x: auto; }
      .dep-stats table { width: 100%; border-collapse: collapse; }
      .dep-stats th, .dep-stats td { padding: .55rem .65rem; border-bottom: 1px solid var(--primary-low); text-align: left; white-space: nowrap; }
      @media (max-width: 900px) { .dep-stats__grid { grid-template-columns: repeat(2, 1fr); } }
      @media (max-width: 700px) { .dep-stats__hero, .dep-stats__toolbar { flex-direction: column; align-items: stretch; } .dep-stats__grid { grid-template-columns: 1fr; } }
    </style>
    <div class="dep-stats">
      <section class="dep-stats__hero">
        <div class="dep-stats__copy">
          <h1>{{i18n "admin.disify_email_protection.statistics.title"}}</h1>
          <p class="dep-stats__muted">{{i18n "admin.disify_email_protection.statistics.description"}}</p>
        </div>
        <div class="dep-stats__actions">
          <a class="btn" href={{overviewUrl}}>{{i18n "admin.disify_email_protection.statistics.back"}}</a>
        </div>
      </section>
      <section class="dep-stats__panel">
        <div class="dep-stats__toolbar">
          <div class="dep-stats__copy">
            <h2>{{i18n "admin.disify_email_protection.statistics.period_title"}}</h2>
            <p class="dep-stats__muted">{{i18n "admin.disify_email_protection.statistics.period_description"}}</p>
          </div>
          <select class="dep-stats__control" value={{@controller.period}} {{on "change" @controller.changePeriod}} aria-label={{i18n "admin.disify_email_protection.statistics.period_label"}}>
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
            <div class="dep-stats__metric"><div class="dep-stats__label">{{i18n "admin.disify_email_protection.statistics.metric_checks"}}</div><div class="dep-stats__value">{{@controller.data.totals.checked}}</div></div>
            <div class="dep-stats__metric"><div class="dep-stats__label">{{i18n "admin.disify_email_protection.statistics.metric_blocked_disposable"}}</div><div class="dep-stats__value">{{@controller.data.totals.blocked_disposable}}</div></div>
            <div class="dep-stats__metric"><div class="dep-stats__label">{{i18n "admin.disify_email_protection.statistics.metric_blocked_no_mx"}}</div><div class="dep-stats__value">{{@controller.data.totals.blocked_no_mx}}</div></div>
            <div class="dep-stats__metric"><div class="dep-stats__label">{{i18n "admin.disify_email_protection.statistics.metric_fail_open"}}</div><div class="dep-stats__value">{{@controller.data.totals.fail_open}}</div></div>
            <div class="dep-stats__metric"><div class="dep-stats__label">{{i18n "admin.disify_email_protection.statistics.metric_monitored"}}</div><div class="dep-stats__value">{{@controller.data.totals.monitored}}</div></div>
            <div class="dep-stats__metric"><div class="dep-stats__label">{{i18n "admin.disify_email_protection.statistics.metric_reviewed"}}</div><div class="dep-stats__value">{{@controller.data.totals.reviewed}}</div></div>
            <div class="dep-stats__metric"><div class="dep-stats__label">{{i18n "admin.disify_email_protection.statistics.metric_api_calls"}}</div><div class="dep-stats__value">{{@controller.data.totals.api_calls}}</div></div>
            <div class="dep-stats__metric"><div class="dep-stats__label">{{i18n "admin.disify_email_protection.statistics.metric_cache_hits"}}</div><div class="dep-stats__value">{{@controller.data.totals.cache_hits}}</div></div>
          </div>
        </section>
        <section class="dep-stats__panel dep-stats__table-wrap">
          <h2>{{i18n "admin.disify_email_protection.statistics.daily_activity"}}</h2>
          <table>
            <thead><tr><th>{{i18n "admin.disify_email_protection.statistics.col_date"}}</th><th>{{i18n "admin.disify_email_protection.statistics.metric_checks"}}</th><th>{{i18n "admin.disify_email_protection.statistics.col_allowed"}}</th><th>{{i18n "admin.disify_email_protection.statistics.metric_monitored"}}</th><th>{{i18n "admin.disify_email_protection.statistics.metric_reviewed"}}</th><th>{{i18n "admin.disify_email_protection.statistics.metric_blocked_disposable"}}</th><th>{{i18n "admin.disify_email_protection.statistics.metric_blocked_no_mx"}}</th><th>{{i18n "admin.disify_email_protection.statistics.metric_fail_open"}}</th><th>{{i18n "admin.disify_email_protection.statistics.metric_api_calls"}}</th><th>{{i18n "admin.disify_email_protection.statistics.metric_cache_hits"}}</th><th>{{i18n "admin.disify_email_protection.statistics.col_average_latency"}}</th></tr></thead>
            <tbody>
              {{#each @controller.data.daily as |day|}}
                <tr><td>{{day.stat_date}}</td><td>{{day.checked}}</td><td>{{day.allowed}}</td><td>{{day.monitored}}</td><td>{{day.reviewed}}</td><td>{{day.blocked_disposable}}</td><td>{{day.blocked_no_mx}}</td><td>{{day.fail_open}}</td><td>{{day.api_calls}}</td><td>{{day.cache_hits}}</td><td>{{day.average_latency_ms}}</td></tr>
              {{/each}}
            </tbody>
          </table>
        </section>
      {{/if}}
    </div>
  </template>
);

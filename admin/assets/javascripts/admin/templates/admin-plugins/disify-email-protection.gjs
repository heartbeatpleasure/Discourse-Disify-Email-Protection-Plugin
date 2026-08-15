import RouteTemplate from "ember-route-template";
import getURL from "discourse/lib/get-url";
import { i18n } from "discourse-i18n";

const settingsUrl = getURL(
  "/admin/site_settings/category/all_results?filter=disify_email_protection"
);
const healthUrl = getURL("/admin/plugins/disify-email-protection-health");
const statisticsUrl = getURL(
  "/admin/plugins/disify-email-protection-statistics"
);
const reviewUrl = getURL("/admin/plugins/disify-email-protection-review");
const toolsUrl = getURL("/admin/plugins/disify-email-protection-tools");

export default RouteTemplate(
  <template>
    <style>
      .dep-admin {
        --dep-surface: var(--secondary);
        --dep-border: var(--primary-low);
        --dep-muted: var(--primary-medium);
        display: flex;
        flex-direction: column;
        gap: 1rem;
      }
      .dep-admin h1, .dep-admin h2, .dep-admin h3, .dep-admin p { margin: 0; }
      .dep-admin__hero, .dep-admin__card, .dep-admin__metric {
        border: 1px solid var(--dep-border);
        border-radius: 18px;
        background: var(--dep-surface);
        box-shadow: 0 1px 2px rgb(0 0 0 / 3%);
      }
      .dep-admin__hero {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: 1rem;
        padding: 1.25rem 1.35rem;
      }
      .dep-admin__hero-copy { display: grid; min-width: 0; flex: 1 1 auto; gap: .45rem; max-width: 760px; }
      .dep-admin__hero > .btn { flex: 0 0 auto; margin-left: auto; white-space: nowrap; }
      .dep-admin__hero-copy p, .dep-admin__muted, .dep-admin__card p { color: var(--dep-muted); }
      .dep-admin__status-row, .dep-admin__metrics {
        display: grid;
        grid-template-columns: repeat(4, minmax(0, 1fr));
        gap: .8rem;
      }
      .dep-admin__metric { padding: .85rem 1rem; }
      .dep-admin__metric-label { color: var(--dep-muted); font-size: var(--font-down-1); font-weight: 700; }
      .dep-admin__metric-value { margin-top: .25rem; font-size: var(--font-up-2); font-weight: 700; overflow-wrap: anywhere; }
      .dep-admin__section { display: grid; gap: .7rem; }
      .dep-admin__grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 1rem; }
      .dep-admin__card {
        display: flex;
        min-height: 165px;
        flex-direction: column;
        gap: .8rem;
        padding: 1rem 1.1rem;
        color: var(--primary);
        text-decoration: none;
        transition: border-color .12s ease, box-shadow .12s ease, transform .12s ease;
      }
      .dep-admin__card:hover, .dep-admin__card:focus {
        border-color: var(--tertiary-medium);
        box-shadow: 0 6px 18px rgb(0 0 0 / 6%);
        color: var(--primary);
        text-decoration: none;
        transform: translateY(-1px);
      }
      .dep-admin__card.is-primary {
        border-color: var(--tertiary-low);
        background: linear-gradient(180deg, var(--secondary), var(--tertiary-very-low));
      }
      .dep-admin__badge {
        display: inline-flex;
        width: max-content;
        padding: .35rem .55rem;
        border: 1px solid var(--primary-low);
        border-radius: 999px;
        background: var(--primary-very-low);
        color: var(--primary-medium);
        font-size: var(--font-down-1);
        line-height: 1;
      }
      .dep-admin__badge.is-primary { border-color: var(--tertiary-low); background: var(--tertiary-low); color: var(--tertiary); }
      .dep-admin__action { margin-top: auto; color: var(--tertiary); font-weight: 600; }
      @media (max-width: 850px) { .dep-admin__status-row, .dep-admin__metrics { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
      @media (max-width: 700px) {
        .dep-admin__hero { flex-direction: column; }
        .dep-admin__hero > .btn { align-self: flex-end; margin-left: 0; }
      }
      @media (max-width: 600px) {
        .dep-admin__status-row, .dep-admin__metrics { grid-template-columns: 1fr; }
      }
    </style>

    <div class="dep-admin">
      <section class="dep-admin__hero">
        <div class="dep-admin__hero-copy">
          <h1>{{i18n "admin.disify_email_protection.title"}}</h1>
          <p>{{i18n "admin.disify_email_protection.description"}}</p>
        </div>
        <a class="btn btn-primary" href={{settingsUrl}}>
          {{i18n "admin.disify_email_protection.open_settings"}}
        </a>
      </section>

      <section class="dep-admin__section">
        <h2>{{i18n "admin.disify_email_protection.current_status"}}</h2>
        <div class="dep-admin__status-row">
          <div class="dep-admin__metric">
            <div class="dep-admin__metric-label">{{i18n "admin.disify_email_protection.status_label"}}</div>
            <div class="dep-admin__metric-value">{{@model.health.overall}}</div>
          </div>
          <div class="dep-admin__metric">
            <div class="dep-admin__metric-label">{{i18n "admin.disify_email_protection.protection_mode_label"}}</div>
            <div class="dep-admin__metric-value">{{@model.health.configuration.mode}}</div>
          </div>
          <div class="dep-admin__metric">
            <div class="dep-admin__metric-label">{{i18n "admin.disify_email_protection.checks_today_label"}}</div>
            <div class="dep-admin__metric-value">{{@model.today.checked}}</div>
          </div>
          <div class="dep-admin__metric">
            <div class="dep-admin__metric-label">{{i18n "admin.disify_email_protection.pending_reviews_label"}}</div>
            <div class="dep-admin__metric-value">{{@model.pending_reviews}}</div>
          </div>
        </div>
      </section>

      <section class="dep-admin__section">
        <div>
          <h2>{{i18n "admin.disify_email_protection.overview_title"}}</h2>
          <p class="dep-admin__muted">{{i18n "admin.disify_email_protection.overview_description"}}</p>
        </div>
        <div class="dep-admin__grid">
          <a class="dep-admin__card is-primary" href={{settingsUrl}}>
            <span class="dep-admin__badge is-primary">{{i18n "admin.disify_email_protection.category_configuration"}}</span>
            <h3>{{i18n "admin.disify_email_protection.open_settings"}}</h3>
            <p>{{i18n "admin.disify_email_protection.settings_description"}}</p>
            <span class="dep-admin__action">{{i18n "admin.disify_email_protection.open_settings"}}</span>
          </a>
          <a class="dep-admin__card" href={{healthUrl}}>
            <span class="dep-admin__badge">{{i18n "admin.disify_email_protection.category_monitoring"}}</span>
            <h3>{{i18n "admin.disify_email_protection.health.short_title"}}</h3>
            <p>{{i18n "admin.disify_email_protection.health.description"}}</p>
            <span class="dep-admin__action">{{i18n "admin.disify_email_protection.open_tool"}}</span>
          </a>
          <a class="dep-admin__card" href={{statisticsUrl}}>
            <span class="dep-admin__badge">{{i18n "admin.disify_email_protection.category_monitoring"}}</span>
            <h3>{{i18n "admin.disify_email_protection.statistics.short_title"}}</h3>
            <p>{{i18n "admin.disify_email_protection.statistics.description"}}</p>
            <span class="dep-admin__action">{{i18n "admin.disify_email_protection.open_tool"}}</span>
          </a>
          <a class="dep-admin__card" href={{reviewUrl}}>
            <span class="dep-admin__badge">{{i18n "admin.disify_email_protection.category_moderation"}}</span>
            <h3>{{i18n "admin.disify_email_protection.review.short_title"}}</h3>
            <p>{{i18n "admin.disify_email_protection.review.description"}}</p>
            <span class="dep-admin__action">{{i18n "admin.disify_email_protection.open_tool"}}</span>
          </a>
          <a class="dep-admin__card" href={{toolsUrl}}>
            <span class="dep-admin__badge">{{i18n "admin.disify_email_protection.category_operations"}}</span>
            <h3>{{i18n "admin.disify_email_protection.tools.short_title"}}</h3>
            <p>{{i18n "admin.disify_email_protection.tools.description"}}</p>
            <span class="dep-admin__action">{{i18n "admin.disify_email_protection.open_tool"}}</span>
          </a>
        </div>
      </section>
    </div>
  </template>
);

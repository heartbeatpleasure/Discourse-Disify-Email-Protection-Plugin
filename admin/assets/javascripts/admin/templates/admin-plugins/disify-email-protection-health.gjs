import { on } from "@ember/modifier";
import RouteTemplate from "ember-route-template";
import getURL from "discourse/lib/get-url";
import { i18n } from "discourse-i18n";

const overviewUrl = getURL("/admin/plugins/disify-email-protection");
const settingsUrl = getURL(
  "/admin/site_settings/category/all_results?filter=disify_email_protection"
);

export default RouteTemplate(
  <template>
    <style>
      .dep-page {
        --dep-surface: var(--secondary);
        --dep-surface-alt: var(--primary-very-low);
        --dep-border: var(--primary-low);
        --dep-muted: var(--primary-medium);
        display: flex;
        flex-direction: column;
        gap: 1rem;
      }
      .dep-page h1, .dep-page h2, .dep-page p { margin: 0; }
      .dep-page__hero, .dep-page__panel {
        min-width: 0;
        padding: 1.2rem 1.35rem;
        border: 1px solid var(--dep-border);
        border-radius: 18px;
        background: var(--dep-surface);
        box-shadow: 0 1px 2px rgb(0 0 0 / 3%);
      }
      .dep-page__hero, .dep-page__panel-header {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: 1rem;
      }
      .dep-page__copy {
        display: flex;
        min-width: 0;
        flex: 1 1 auto;
        flex-direction: column;
        gap: .35rem;
      }
      .dep-page__muted { color: var(--dep-muted); }
      .dep-page__hero-actions {
        display: flex;
        flex: 0 0 auto;
        flex-wrap: nowrap;
        align-items: center;
        justify-content: flex-end;
        gap: .5rem;
        margin-left: auto;
      }
      .dep-page__hero-actions .btn,
      .dep-page__panel-header > .btn { white-space: nowrap; }
      .dep-page__panel-header > .btn { flex: 0 0 auto; }
      .dep-page__grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: .75rem; margin-top: .85rem; }
      .dep-page__item { min-width: 0; padding: .75rem; border-radius: 12px; background: var(--dep-surface-alt); }
      .dep-page__label { color: var(--dep-muted); font-size: var(--font-down-1); font-weight: 700; }
      .dep-page__value { margin-top: .2rem; overflow-wrap: anywhere; font-weight: 600; }
      @media (max-width: 900px) {
        .dep-page__hero { flex-direction: column; }
        .dep-page__hero-actions { align-self: flex-end; flex-wrap: wrap; margin-left: 0; }
      }
      @media (max-width: 800px) { .dep-page__grid { grid-template-columns: 1fr 1fr; } }
      @media (max-width: 650px) {
        .dep-page__panel-header { flex-direction: column; }
        .dep-page__panel-header > .btn { align-self: flex-end; }
        .dep-page__grid { grid-template-columns: 1fr; }
      }
    </style>
    <div class="dep-page">
      <section class="dep-page__hero">
        <div class="dep-page__copy">
          <h1>{{i18n "admin.disify_email_protection.health.title"}}</h1>
          <p class="dep-page__muted">{{i18n "admin.disify_email_protection.health.description"}}</p>
        </div>
        <div class="dep-page__hero-actions">
          <a class="btn" href={{overviewUrl}}>{{i18n "admin.disify_email_protection.health.back"}}</a>
          <a class="btn" href={{settingsUrl}}>{{i18n "admin.disify_email_protection.open_settings"}}</a>
          <button class="btn" type="button" {{on "click" @controller.loadHealth}} disabled={{@controller.isLoading}}>
            {{i18n "admin.disify_email_protection.health.refresh"}}
          </button>
          <button class="btn btn-primary" type="button" {{on "click" @controller.runTest}} disabled={{@controller.isTesting}}>
            {{i18n "admin.disify_email_protection.health.test"}}
          </button>
        </div>
      </section>

      {{#if @controller.data}}
        <section class="dep-page__panel">
          <h2>{{i18n "admin.disify_email_protection.health.current_state"}}</h2>
          <div class="dep-page__grid">
            <div class="dep-page__item"><div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_overall"}}</div><div class="dep-page__value">{{@controller.data.overall}}</div></div>
            <div class="dep-page__item"><div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_enabled"}}</div><div class="dep-page__value">{{@controller.data.configuration.enabled}}</div></div>
            <div class="dep-page__item"><div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_mode"}}</div><div class="dep-page__value">{{@controller.data.configuration.mode}}</div></div>
            <div class="dep-page__item"><div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_api_key_configured"}}</div><div class="dep-page__value">{{@controller.data.configuration.api_key_configured}}</div></div>
            <div class="dep-page__item"><div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_auth_mode"}}</div><div class="dep-page__value">{{@controller.data.configuration.auth_mode}}</div></div>
            <div class="dep-page__item"><div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_fail_open"}}</div><div class="dep-page__value">{{@controller.data.configuration.fail_open}}</div></div>
          </div>
        </section>

        <section class="dep-page__panel">
          <h2>{{i18n "admin.disify_email_protection.health.provider_quota"}}</h2>
          <div class="dep-page__grid">
            <div class="dep-page__item"><div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_last_success"}}</div><div class="dep-page__value">{{@controller.data.provider.last_success_at}}</div></div>
            <div class="dep-page__item"><div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_last_error"}}</div><div class="dep-page__value">{{@controller.data.provider.last_error_code}}</div></div>
            <div class="dep-page__item"><div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_last_latency"}}</div><div class="dep-page__value">{{@controller.data.provider.last_latency_ms}}</div></div>
            <div class="dep-page__item"><div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_rate_limit"}}</div><div class="dep-page__value">{{@controller.data.provider.rate_limit_limit}}</div></div>
            <div class="dep-page__item"><div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_remaining"}}</div><div class="dep-page__value">{{@controller.data.provider.rate_limit_remaining}}</div></div>
            <div class="dep-page__item"><div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_reset_at"}}</div><div class="dep-page__value">{{@controller.data.provider.reset_at}}</div></div>
          </div>
        </section>

        <section class="dep-page__panel">
          <div class="dep-page__panel-header">
            <div class="dep-page__copy">
              <h2>{{i18n "admin.disify_email_protection.health.circuit_breaker"}}</h2>
              <p class="dep-page__muted">{{i18n "admin.disify_email_protection.health.circuit_breaker_description"}}</p>
            </div>
            <button class="btn" type="button" {{on "click" @controller.resetCircuit}} disabled={{@controller.isResetting}}>
              {{i18n "admin.disify_email_protection.health.reset_circuit"}}
            </button>
          </div>
          <div class="dep-page__grid">
            <div class="dep-page__item"><div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_state"}}</div><div class="dep-page__value">{{@controller.data.circuit_breaker.state}}</div></div>
            <div class="dep-page__item"><div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_reason"}}</div><div class="dep-page__value">{{@controller.data.circuit_breaker.reason}}</div></div>
            <div class="dep-page__item"><div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_open_until"}}</div><div class="dep-page__value">{{@controller.data.circuit_breaker.open_until}}</div></div>
          </div>
        </section>

        <section class="dep-page__panel">
          <h2>{{i18n "admin.disify_email_protection.health.privacy_posture"}}</h2>
          <div class="dep-page__grid">
            <div class="dep-page__item"><div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_raw_email_stored"}}</div><div class="dep-page__value">{{@controller.data.privacy.raw_email_stored_in_plugin_tables}}</div></div>
            <div class="dep-page__item"><div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_api_key_exposed"}}</div><div class="dep-page__value">{{@controller.data.privacy.api_key_exposed_to_client}}</div></div>
            <div class="dep-page__item"><div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_full_response_stored"}}</div><div class="dep-page__value">{{@controller.data.privacy.full_api_response_stored}}</div></div>
          </div>
        </section>
      {{/if}}
    </div>
  </template>
);

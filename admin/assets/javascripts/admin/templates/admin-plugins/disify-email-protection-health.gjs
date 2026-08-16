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
      .dep-page__grid {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: .75rem;
        margin-top: .85rem;
      }
      .dep-page__item {
        min-width: 0;
        padding: .75rem;
        border-radius: 12px;
        background: var(--dep-surface-alt);
      }
      .dep-page__label-row {
        position: relative;
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: .45rem;
        min-width: 0;
      }
      .dep-page__label {
        min-width: 0;
        color: var(--dep-muted);
        font-size: var(--font-down-1);
        font-weight: 700;
      }
      .dep-page__value {
        margin-top: .2rem;
        overflow-wrap: anywhere;
        font-weight: 600;
      }
      .dep-page__boolean {
        display: inline-flex;
        align-items: center;
        min-height: 28px;
        padding: .2rem .55rem;
        border: 1px solid var(--dep-border);
        border-radius: 999px;
        background: var(--secondary);
        font-size: var(--font-down-1);
        font-weight: 700;
      }
      .dep-page__info {
        display: inline-flex;
        flex: 0 0 auto;
        align-items: center;
        justify-content: center;
        width: 1.35rem;
        height: 1.35rem;
        border: 1px solid var(--tertiary);
        border-radius: 999px;
        background: var(--tertiary);
        color: var(--secondary);
        font-size: .76rem;
        font-weight: 700;
        line-height: 1;
        cursor: help;
        user-select: none;
      }
      .dep-page__tooltip {
        position: absolute;
        bottom: calc(100% + .5rem);
        right: 0;
        z-index: 3000;
        width: min(22rem, calc(100vw - 4rem));
        max-width: calc(100vw - 4rem);
        padding: .7rem .8rem;
        border: 1px solid var(--dep-border);
        border-radius: 12px;
        background: var(--secondary);
        color: var(--primary-high);
        box-shadow: 0 8px 24px rgb(0 0 0 / 12%);
        font-size: var(--font-down-1);
        font-weight: 400;
        line-height: 1.45;
        white-space: normal;
        opacity: 0;
        pointer-events: none;
        transform: translateY(.15rem);
        transition: opacity .14s ease, transform .14s ease;
      }
      .dep-page__label-row.is-tooltip-left .dep-page__tooltip {
        right: auto;
        left: 0;
      }
      .dep-page__info:hover + .dep-page__tooltip,
      .dep-page__info:focus-visible + .dep-page__tooltip,
      .dep-page__info:focus + .dep-page__tooltip {
        opacity: 1;
        transform: translateY(0);
      }
      @media (max-width: 900px) {
        .dep-page__hero { flex-direction: column; }
        .dep-page__hero-actions { align-self: flex-end; flex-wrap: wrap; margin-left: 0; }
      }
      @media (max-width: 800px) {
        .dep-page__grid { grid-template-columns: 1fr 1fr; }
      }
      @media (max-width: 650px) {
        .dep-page__panel-header { flex-direction: column; }
        .dep-page__panel-header > .btn { align-self: flex-end; }
        .dep-page__grid { grid-template-columns: 1fr; }
        .dep-page__label-row .dep-page__tooltip,
        .dep-page__label-row.is-tooltip-left .dep-page__tooltip {
          right: 0;
          left: auto;
        }
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
          <div class="dep-page__panel-header">
            <div class="dep-page__copy">
              <h2>{{i18n "admin.disify_email_protection.health.provider_quota"}}</h2>
              <p class="dep-page__muted">{{i18n "admin.disify_email_protection.health.provider_limits_description"}}</p>
            </div>
          </div>
          <div class="dep-page__grid">
            <div class="dep-page__item">
              <div class="dep-page__label-row is-tooltip-left">
                <div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_last_success"}}</div>
                <span class="dep-page__info" tabindex="0" aria-label={{i18n "admin.disify_email_protection.health.info_last_success"}}>i</span>
                <span class="dep-page__tooltip" role="tooltip">{{i18n "admin.disify_email_protection.health.info_last_success"}}</span>
              </div>
              <div class="dep-page__value">{{@controller.data.provider.last_success_at_display}}</div>
            </div>
            <div class="dep-page__item">
              <div class="dep-page__label-row">
                <div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_last_error"}}</div>
                <span class="dep-page__info" tabindex="0" aria-label={{i18n "admin.disify_email_protection.health.info_last_error"}}>i</span>
                <span class="dep-page__tooltip" role="tooltip">{{i18n "admin.disify_email_protection.health.info_last_error"}}</span>
              </div>
              <div class="dep-page__value">{{@controller.data.provider.last_error_code_display}}</div>
            </div>
            <div class="dep-page__item">
              <div class="dep-page__label-row">
                <div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_last_latency"}}</div>
                <span class="dep-page__info" tabindex="0" aria-label={{i18n "admin.disify_email_protection.health.info_last_latency"}}>i</span>
                <span class="dep-page__tooltip" role="tooltip">{{i18n "admin.disify_email_protection.health.info_last_latency"}}</span>
              </div>
              <div class="dep-page__value">{{@controller.data.provider.last_latency_ms_display}}</div>
            </div>
            <div class="dep-page__item">
              <div class="dep-page__label-row is-tooltip-left">
                <div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_rate_limit"}}</div>
                <span class="dep-page__info" tabindex="0" aria-label={{i18n "admin.disify_email_protection.health.info_rate_limit"}}>i</span>
                <span class="dep-page__tooltip" role="tooltip">{{i18n "admin.disify_email_protection.health.info_rate_limit"}}</span>
              </div>
              <div class="dep-page__value">{{@controller.data.provider.rate_limit_limit_display}}</div>
            </div>
            <div class="dep-page__item">
              <div class="dep-page__label-row">
                <div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_remaining"}}</div>
                <span class="dep-page__info" tabindex="0" aria-label={{i18n "admin.disify_email_protection.health.info_remaining"}}>i</span>
                <span class="dep-page__tooltip" role="tooltip">{{i18n "admin.disify_email_protection.health.info_remaining"}}</span>
              </div>
              <div class="dep-page__value">{{@controller.data.provider.rate_limit_remaining_display}}</div>
            </div>
            <div class="dep-page__item">
              <div class="dep-page__label-row">
                <div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_reset_at"}}</div>
                <span class="dep-page__info" tabindex="0" aria-label={{i18n "admin.disify_email_protection.health.info_reset_at"}}>i</span>
                <span class="dep-page__tooltip" role="tooltip">{{i18n "admin.disify_email_protection.health.info_reset_at"}}</span>
              </div>
              <div class="dep-page__value">{{@controller.data.provider.reset_at_display}}</div>
            </div>
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
            <div class="dep-page__item"><div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_open_until"}}</div><div class="dep-page__value">{{@controller.data.circuit_breaker.open_until_display}}</div></div>
          </div>
        </section>

        <section class="dep-page__panel">
          <div class="dep-page__panel-header">
            <div class="dep-page__copy">
              <h2>{{i18n "admin.disify_email_protection.health.privacy_posture"}}</h2>
              <p class="dep-page__muted">{{i18n "admin.disify_email_protection.health.privacy_posture_description"}}</p>
            </div>
          </div>
          <div class="dep-page__grid">
            <div class="dep-page__item">
              <div class="dep-page__label-row is-tooltip-left">
                <div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_raw_email_stored"}}</div>
                <span class="dep-page__info" tabindex="0" aria-label={{i18n "admin.disify_email_protection.health.info_raw_email_stored"}}>i</span>
                <span class="dep-page__tooltip" role="tooltip">{{i18n "admin.disify_email_protection.health.info_raw_email_stored"}}</span>
              </div>
              <div class="dep-page__value"><span class="dep-page__boolean">{{if @controller.data.privacy.raw_email_stored_in_plugin_tables (i18n "admin.disify_email_protection.health.value_yes") (i18n "admin.disify_email_protection.health.value_no")}}</span></div>
            </div>
            <div class="dep-page__item">
              <div class="dep-page__label-row">
                <div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_api_key_exposed"}}</div>
                <span class="dep-page__info" tabindex="0" aria-label={{i18n "admin.disify_email_protection.health.info_api_key_exposed"}}>i</span>
                <span class="dep-page__tooltip" role="tooltip">{{i18n "admin.disify_email_protection.health.info_api_key_exposed"}}</span>
              </div>
              <div class="dep-page__value"><span class="dep-page__boolean">{{if @controller.data.privacy.api_key_exposed_to_client (i18n "admin.disify_email_protection.health.value_yes") (i18n "admin.disify_email_protection.health.value_no")}}</span></div>
            </div>
            <div class="dep-page__item">
              <div class="dep-page__label-row">
                <div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_full_response_stored"}}</div>
                <span class="dep-page__info" tabindex="0" aria-label={{i18n "admin.disify_email_protection.health.info_full_response_stored"}}>i</span>
                <span class="dep-page__tooltip" role="tooltip">{{i18n "admin.disify_email_protection.health.info_full_response_stored"}}</span>
              </div>
              <div class="dep-page__value"><span class="dep-page__boolean">{{if @controller.data.privacy.full_api_response_stored (i18n "admin.disify_email_protection.health.value_yes") (i18n "admin.disify_email_protection.health.value_no")}}</span></div>
            </div>
            <div class="dep-page__item">
              <div class="dep-page__label-row is-tooltip-left">
                <div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_hmac_correlation"}}</div>
                <span class="dep-page__info" tabindex="0" aria-label={{i18n "admin.disify_email_protection.health.info_hmac_correlation"}}>i</span>
                <span class="dep-page__tooltip" role="tooltip">{{i18n "admin.disify_email_protection.health.info_hmac_correlation"}}</span>
              </div>
              <div class="dep-page__value"><span class="dep-page__boolean">{{if @controller.data.privacy.email_hmac_used_for_correlation (i18n "admin.disify_email_protection.health.value_yes") (i18n "admin.disify_email_protection.health.value_no")}}</span></div>
            </div>
          </div>
        </section>
      {{/if}}
    </div>
  </template>
);

import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import RouteTemplate from "ember-route-template";
import getURL from "discourse/lib/get-url";
import { eq } from "discourse/truth-helpers";
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
      .dep-page h1, .dep-page h2, .dep-page h3, .dep-page p { margin: 0; }
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
      .dep-page__info:hover,
      .dep-page__info:focus-visible,
      .dep-page__info[aria-expanded="true"] {
        border-color: var(--tertiary, currentColor);
        background: var(--tertiary-low, var(--primary-low));
        color: var(--tertiary, currentColor);
        outline: none;
      }
      .dep-page__info:focus-visible {
        outline: 2px solid var(--tertiary, currentColor);
        outline-offset: 2px;
      }
      .dep-page__info-backdrop {
        position: fixed;
        inset: 0;
        z-index: 19998;
        border: 0;
        padding: 0;
        margin: 0;
        background: transparent;
        cursor: default;
      }
      .dep-page__info-popover {
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
      .dep-page__info-popover-header {
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
      .dep-page__info-popover-header > div {
        display: grid;
        gap: .15rem;
        min-width: 0;
      }
      .dep-page__info-popover-kicker {
        color: var(--tertiary);
        font-size: var(--font-down-1);
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: .04em;
      }
      .dep-page__info-popover-close {
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
      .dep-page__info-popover-close:hover,
      .dep-page__info-popover-close:focus-visible {
        background: var(--primary-very-low);
        outline: 2px solid var(--tertiary);
        outline-offset: 1px;
      }
      .dep-page__info-popover-body {
        color: var(--primary-high);
        font-size: var(--font-down-1);
        line-height: 1.5;
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
            <div class="dep-page__item">
              <div class="dep-page__label-row">
                <div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_mode"}}</div>
                <button class="dep-page__info" type="button" aria-label={{i18n "admin.disify_email_protection.health.info_mode"}} aria-expanded={{eq @controller.activeInfoKey "mode"}} aria-controls="dep-health-info-overlay" {{on "click" (fn @controller.toggleInfo "mode")}} {{on "keydown" (fn @controller.handleInfoTriggerKeydown "mode")}}>i</button>
              </div>
              <div class="dep-page__value">{{@controller.data.configuration.mode}}</div>
            </div>
            <div class="dep-page__item"><div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_api_key_configured"}}</div><div class="dep-page__value">{{@controller.data.configuration.api_key_configured}}</div></div>
            <div class="dep-page__item">
              <div class="dep-page__label-row">
                <div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_auth_mode"}}</div>
                <button class="dep-page__info" type="button" aria-label={{i18n "admin.disify_email_protection.health.info_auth_mode"}} aria-expanded={{eq @controller.activeInfoKey "auth_mode"}} aria-controls="dep-health-info-overlay" {{on "click" (fn @controller.toggleInfo "auth_mode")}} {{on "keydown" (fn @controller.handleInfoTriggerKeydown "auth_mode")}}>i</button>
              </div>
              <div class="dep-page__value">{{@controller.data.configuration.auth_mode}}</div>
            </div>
            <div class="dep-page__item">
              <div class="dep-page__label-row">
                <div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_fail_open"}}</div>
                <button class="dep-page__info" type="button" aria-label={{i18n "admin.disify_email_protection.health.info_fail_open"}} aria-expanded={{eq @controller.activeInfoKey "fail_open"}} aria-controls="dep-health-info-overlay" {{on "click" (fn @controller.toggleInfo "fail_open")}} {{on "keydown" (fn @controller.handleInfoTriggerKeydown "fail_open")}}>i</button>
              </div>
              <div class="dep-page__value">{{@controller.data.configuration.fail_open}}</div>
            </div>
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
              <div class="dep-page__label-row">
                <div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_last_check"}}</div>
                <button class="dep-page__info" type="button" aria-label={{i18n "admin.disify_email_protection.health.info_last_check"}} aria-expanded={{eq @controller.activeInfoKey "last_check"}} aria-controls="dep-health-info-overlay" {{on "click" (fn @controller.toggleInfo "last_check")}} {{on "keydown" (fn @controller.handleInfoTriggerKeydown "last_check")}}>i</button>
              </div>
              <div class="dep-page__value">{{@controller.data.provider.last_check_at_display}}</div>
            </div>
            <div class="dep-page__item">
              <div class="dep-page__label-row">
                <div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_last_error"}}</div>
                <button class="dep-page__info" type="button" aria-label={{i18n "admin.disify_email_protection.health.info_last_error"}} aria-expanded={{eq @controller.activeInfoKey "last_error"}} aria-controls="dep-health-info-overlay" {{on "click" (fn @controller.toggleInfo "last_error")}} {{on "keydown" (fn @controller.handleInfoTriggerKeydown "last_error")}}>i</button>
              </div>
              <div class="dep-page__value">{{@controller.data.provider.last_error_code_display}}</div>
            </div>
            <div class="dep-page__item">
              <div class="dep-page__label-row">
                <div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_last_latency"}}</div>
                <button class="dep-page__info" type="button" aria-label={{i18n "admin.disify_email_protection.health.info_last_latency"}} aria-expanded={{eq @controller.activeInfoKey "last_latency"}} aria-controls="dep-health-info-overlay" {{on "click" (fn @controller.toggleInfo "last_latency")}} {{on "keydown" (fn @controller.handleInfoTriggerKeydown "last_latency")}}>i</button>
              </div>
              <div class="dep-page__value">{{@controller.data.provider.last_latency_ms_display}}</div>
            </div>
            <div class="dep-page__item">
              <div class="dep-page__label-row">
                <div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_rate_limit"}}</div>
                <button class="dep-page__info" type="button" aria-label={{i18n "admin.disify_email_protection.health.info_rate_limit"}} aria-expanded={{eq @controller.activeInfoKey "rate_limit"}} aria-controls="dep-health-info-overlay" {{on "click" (fn @controller.toggleInfo "rate_limit")}} {{on "keydown" (fn @controller.handleInfoTriggerKeydown "rate_limit")}}>i</button>
              </div>
              <div class="dep-page__value">{{@controller.data.provider.rate_limit_limit_display}}</div>
            </div>
            {{#if @controller.data.provider.reset_at}}
              <div class="dep-page__item">
                <div class="dep-page__label-row">
                  <div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_reset_at"}}</div>
                  <button class="dep-page__info" type="button" aria-label={{i18n "admin.disify_email_protection.health.info_reset_at"}} aria-expanded={{eq @controller.activeInfoKey "reset_at"}} aria-controls="dep-health-info-overlay" {{on "click" (fn @controller.toggleInfo "reset_at")}} {{on "keydown" (fn @controller.handleInfoTriggerKeydown "reset_at")}}>i</button>
                </div>
                <div class="dep-page__value">{{@controller.data.provider.reset_at_display}}</div>
              </div>
            {{/if}}
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
              <div class="dep-page__label-row">
                <div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_raw_email_stored"}}</div>
                <button class="dep-page__info" type="button" aria-label={{i18n "admin.disify_email_protection.health.info_raw_email_stored"}} aria-expanded={{eq @controller.activeInfoKey "raw_email_stored"}} aria-controls="dep-health-info-overlay" {{on "click" (fn @controller.toggleInfo "raw_email_stored")}} {{on "keydown" (fn @controller.handleInfoTriggerKeydown "raw_email_stored")}}>i</button>
              </div>
              <div class="dep-page__value"><span class="dep-page__boolean">{{if @controller.data.privacy.raw_email_stored_in_plugin_tables (i18n "admin.disify_email_protection.health.value_yes") (i18n "admin.disify_email_protection.health.value_no")}}</span></div>
            </div>
            <div class="dep-page__item">
              <div class="dep-page__label-row">
                <div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_api_key_exposed"}}</div>
                <button class="dep-page__info" type="button" aria-label={{i18n "admin.disify_email_protection.health.info_api_key_exposed"}} aria-expanded={{eq @controller.activeInfoKey "api_key_exposed"}} aria-controls="dep-health-info-overlay" {{on "click" (fn @controller.toggleInfo "api_key_exposed")}} {{on "keydown" (fn @controller.handleInfoTriggerKeydown "api_key_exposed")}}>i</button>
              </div>
              <div class="dep-page__value"><span class="dep-page__boolean">{{if @controller.data.privacy.api_key_exposed_to_client (i18n "admin.disify_email_protection.health.value_yes") (i18n "admin.disify_email_protection.health.value_no")}}</span></div>
            </div>
            <div class="dep-page__item">
              <div class="dep-page__label-row">
                <div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_full_response_stored"}}</div>
                <button class="dep-page__info" type="button" aria-label={{i18n "admin.disify_email_protection.health.info_full_response_stored"}} aria-expanded={{eq @controller.activeInfoKey "full_response_stored"}} aria-controls="dep-health-info-overlay" {{on "click" (fn @controller.toggleInfo "full_response_stored")}} {{on "keydown" (fn @controller.handleInfoTriggerKeydown "full_response_stored")}}>i</button>
              </div>
              <div class="dep-page__value"><span class="dep-page__boolean">{{if @controller.data.privacy.full_api_response_stored (i18n "admin.disify_email_protection.health.value_yes") (i18n "admin.disify_email_protection.health.value_no")}}</span></div>
            </div>
            <div class="dep-page__item">
              <div class="dep-page__label-row">
                <div class="dep-page__label">{{i18n "admin.disify_email_protection.health.label_hmac_correlation"}}</div>
                <button class="dep-page__info" type="button" aria-label={{i18n "admin.disify_email_protection.health.info_hmac_correlation"}} aria-expanded={{eq @controller.activeInfoKey "hmac_correlation"}} aria-controls="dep-health-info-overlay" {{on "click" (fn @controller.toggleInfo "hmac_correlation")}} {{on "keydown" (fn @controller.handleInfoTriggerKeydown "hmac_correlation")}}>i</button>
              </div>
              <div class="dep-page__value"><span class="dep-page__boolean">{{if @controller.data.privacy.email_hmac_used_for_correlation (i18n "admin.disify_email_protection.health.value_yes") (i18n "admin.disify_email_protection.health.value_no")}}</span></div>
            </div>
          </div>
        </section>
      {{/if}}

      {{#if @controller.activeInfo}}
        <button class="dep-page__info-backdrop" type="button" tabindex="-1" aria-label={{i18n "admin.disify_email_protection.health.info_close"}} {{on "click" @controller.closeInfo}}></button>
        <aside id="dep-health-info-overlay" class={{@controller.infoOverlayClass}} style={{@controller.infoOverlayStyle}} role="dialog" aria-modal="false" aria-label={{@controller.activeInfo.title}} tabindex="-1" {{on "keydown" @controller.handleInfoKeydown}}>
          <div class="dep-page__info-popover-header">
            <div>
              <span class="dep-page__info-popover-kicker">{{i18n "admin.disify_email_protection.health.info_kicker"}}</span>
              <h3>{{@controller.activeInfo.title}}</h3>
            </div>
            <button class="dep-page__info-popover-close" type="button" aria-label={{i18n "admin.disify_email_protection.health.info_close"}} {{on "click" @controller.closeInfo}}>×</button>
          </div>
          <div class="dep-page__info-popover-body">
            <p>{{@controller.activeInfo.body}}</p>
          </div>
        </aside>
      {{/if}}
    </div>
  </template>
);

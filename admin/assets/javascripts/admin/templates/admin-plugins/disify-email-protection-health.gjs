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
      .dep-page { display: grid; gap: 1rem; }
      .dep-page h1, .dep-page h2, .dep-page p { margin: 0; }
      .dep-page__hero, .dep-page__panel { padding: 1rem 1.15rem; border: 1px solid var(--primary-low); border-radius: 16px; background: var(--secondary); }
      .dep-page__hero { display: flex; justify-content: space-between; gap: 1rem; align-items: flex-start; }
      .dep-page__copy { display: grid; gap: .35rem; }
      .dep-page__muted { color: var(--primary-medium); }
      .dep-page__actions { display: flex; flex-wrap: wrap; gap: .5rem; }
      .dep-page__grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: .75rem; }
      .dep-page__item { padding: .75rem; border-radius: 12px; background: var(--primary-very-low); }
      .dep-page__label { color: var(--primary-medium); font-size: var(--font-down-1); font-weight: 700; }
      .dep-page__value { margin-top: .2rem; overflow-wrap: anywhere; font-weight: 600; }
      @media (max-width: 800px) { .dep-page__grid { grid-template-columns: 1fr 1fr; } }
      @media (max-width: 600px) { .dep-page__hero { flex-direction: column; } .dep-page__grid { grid-template-columns: 1fr; } }
    </style>
    <div class="dep-page">
      <section class="dep-page__hero">
        <div class="dep-page__copy">
          <h1>{{i18n "admin.disify_email_protection.health.title"}}</h1>
          <p class="dep-page__muted">{{i18n "admin.disify_email_protection.health.description"}}</p>
        </div>
        <div class="dep-page__actions">
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
          <h2>Current state</h2>
          <div class="dep-page__grid">
            <div class="dep-page__item"><div class="dep-page__label">Overall</div><div class="dep-page__value">{{@controller.data.overall}}</div></div>
            <div class="dep-page__item"><div class="dep-page__label">Enabled</div><div class="dep-page__value">{{@controller.data.configuration.enabled}}</div></div>
            <div class="dep-page__item"><div class="dep-page__label">Mode</div><div class="dep-page__value">{{@controller.data.configuration.mode}}</div></div>
            <div class="dep-page__item"><div class="dep-page__label">API key configured</div><div class="dep-page__value">{{@controller.data.configuration.api_key_configured}}</div></div>
            <div class="dep-page__item"><div class="dep-page__label">Auth mode</div><div class="dep-page__value">{{@controller.data.configuration.auth_mode}}</div></div>
            <div class="dep-page__item"><div class="dep-page__label">Fail-open</div><div class="dep-page__value">{{@controller.data.configuration.fail_open}}</div></div>
          </div>
        </section>

        <section class="dep-page__panel">
          <h2>Provider and quota</h2>
          <div class="dep-page__grid">
            <div class="dep-page__item"><div class="dep-page__label">Last success</div><div class="dep-page__value">{{@controller.data.provider.last_success_at}}</div></div>
            <div class="dep-page__item"><div class="dep-page__label">Last error</div><div class="dep-page__value">{{@controller.data.provider.last_error_code}}</div></div>
            <div class="dep-page__item"><div class="dep-page__label">Last latency (ms)</div><div class="dep-page__value">{{@controller.data.provider.last_latency_ms}}</div></div>
            <div class="dep-page__item"><div class="dep-page__label">Rate limit</div><div class="dep-page__value">{{@controller.data.provider.rate_limit_limit}}</div></div>
            <div class="dep-page__item"><div class="dep-page__label">Remaining</div><div class="dep-page__value">{{@controller.data.provider.rate_limit_remaining}}</div></div>
            <div class="dep-page__item"><div class="dep-page__label">Reset at</div><div class="dep-page__value">{{@controller.data.provider.reset_at}}</div></div>
          </div>
        </section>

        <section class="dep-page__panel">
          <div class="dep-page__actions" style="justify-content: space-between; align-items: center;">
            <div class="dep-page__copy">
              <h2>Circuit breaker</h2>
              <p class="dep-page__muted">Repeated external failures temporarily stop real-time DISIFY calls while normal fail-open policy remains available.</p>
            </div>
            <button class="btn" type="button" {{on "click" @controller.resetCircuit}} disabled={{@controller.isResetting}}>
              {{i18n "admin.disify_email_protection.health.reset_circuit"}}
            </button>
          </div>
          <div class="dep-page__grid">
            <div class="dep-page__item"><div class="dep-page__label">State</div><div class="dep-page__value">{{@controller.data.circuit_breaker.state}}</div></div>
            <div class="dep-page__item"><div class="dep-page__label">Reason</div><div class="dep-page__value">{{@controller.data.circuit_breaker.reason}}</div></div>
            <div class="dep-page__item"><div class="dep-page__label">Open until</div><div class="dep-page__value">{{@controller.data.circuit_breaker.open_until}}</div></div>
          </div>
        </section>

        <section class="dep-page__panel">
          <h2>Privacy posture</h2>
          <div class="dep-page__grid">
            <div class="dep-page__item"><div class="dep-page__label">Raw email stored in plugin tables</div><div class="dep-page__value">{{@controller.data.privacy.raw_email_stored_in_plugin_tables}}</div></div>
            <div class="dep-page__item"><div class="dep-page__label">API key exposed to client</div><div class="dep-page__value">{{@controller.data.privacy.api_key_exposed_to_client}}</div></div>
            <div class="dep-page__item"><div class="dep-page__label">Full provider response stored</div><div class="dep-page__value">{{@controller.data.privacy.full_api_response_stored}}</div></div>
          </div>
        </section>
      {{/if}}
    </div>
  </template>
);

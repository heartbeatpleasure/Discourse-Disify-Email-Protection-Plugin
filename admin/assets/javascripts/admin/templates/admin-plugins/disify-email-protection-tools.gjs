import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import RouteTemplate from "ember-route-template";
import getURL from "discourse/lib/get-url";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

const overviewUrl = getURL("/admin/plugins/disify-email-protection");
const reviewUrl = getURL("/admin/plugins/disify-email-protection-review");

export default RouteTemplate(
  <template>
    <style>
      .dep-tools { display: grid; gap: 1rem; }
      .dep-tools h1, .dep-tools h2, .dep-tools p { margin: 0; }
      .dep-tools__hero, .dep-tools__panel { padding: 1rem 1.15rem; border: 1px solid var(--primary-low); border-radius: 16px; background: var(--secondary); }
      .dep-tools__hero { display: flex; justify-content: space-between; align-items: flex-start; gap: 1rem; }
      .dep-tools__copy { display: grid; gap: .35rem; }
      .dep-tools__muted { color: var(--primary-medium); }
      .dep-tools__actions { display: flex; flex-wrap: wrap; gap: .5rem; align-items: center; }
      .dep-tools__form { display: grid; grid-template-columns: minmax(14rem, 1fr) auto; gap: .6rem; margin-top: .8rem; }
      .dep-tools__form--three { grid-template-columns: minmax(10rem, .6fr) minmax(14rem, 1fr) minmax(14rem, 1fr) auto; }
      .dep-tools__result, .dep-tools__scan { margin-top: .8rem; padding: .8rem; border-radius: 12px; background: var(--primary-very-low); overflow-wrap: anywhere; }
      .dep-tools__grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: .7rem; }
      .dep-tools__item { padding: .7rem; border-radius: 12px; background: var(--primary-very-low); }
      .dep-tools__label { color: var(--primary-medium); font-size: var(--font-down-1); font-weight: 700; }
      .dep-tools__value { margin-top: .2rem; font-weight: 600; overflow-wrap: anywhere; }
      .dep-tools__exceptions { margin-top: .8rem; width: 100%; border-collapse: collapse; }
      .dep-tools__exceptions th, .dep-tools__exceptions td { padding: .5rem .6rem; border-bottom: 1px solid var(--primary-low); text-align: left; vertical-align: top; }
      @media (max-width: 850px) { .dep-tools__form--three { grid-template-columns: 1fr 1fr; } .dep-tools__grid { grid-template-columns: 1fr 1fr; } }
      @media (max-width: 600px) { .dep-tools__hero { flex-direction: column; } .dep-tools__form, .dep-tools__form--three, .dep-tools__grid { grid-template-columns: 1fr; } }
    </style>
    <div class="dep-tools">
      <section class="dep-tools__hero">
        <div class="dep-tools__copy">
          <h1>{{i18n "admin.disify_email_protection.tools.title"}}</h1>
          <p class="dep-tools__muted">{{i18n "admin.disify_email_protection.tools.description"}}</p>
        </div>
        <div class="dep-tools__actions">
          <a class="btn" href={{reviewUrl}}>Review queue</a>
          <a class="btn" href={{overviewUrl}}>{{i18n "admin.disify_email_protection.tools.back"}}</a>
        </div>
      </section>

      <section class="dep-tools__panel">
        <h2>Manual email check</h2>
        <p class="dep-tools__muted">The entered address is sent to DISIFY for this check but is not stored in plugin tables. A matching pending review item is shown when one exists.</p>
        <div class="dep-tools__form">
          <input type="email" value={{@controller.email}} {{on "input" @controller.updateEmail}} placeholder="member@example.com" autocomplete="off" />
          <button class="btn btn-primary" type="button" {{on "click" @controller.checkEmail}} disabled={{@controller.isChecking}}>{{i18n "admin.disify_email_protection.tools.check"}}</button>
        </div>
        {{#if @controller.checkResult}}
          <div class="dep-tools__result">
            <strong>Decision:</strong> {{@controller.checkResult.result.decision}}<br />
            <strong>Reason:</strong> {{@controller.checkResult.result.reason}}<br />
            <strong>Domain:</strong> {{@controller.checkResult.domain}}<br />
            <strong>Confidence:</strong> {{@controller.checkResult.result.confidence}}<br />
            <strong>Signals:</strong> {{@controller.checkResult.result.signals}}<br />
            {{#if @controller.checkResult.pending_review}}
              <strong>Pending review:</strong> #{{@controller.checkResult.pending_review.id}}
            {{/if}}
          </div>
        {{/if}}
      </section>

      <section class="dep-tools__panel">
        <h2>Existing-user scan</h2>
        <p class="dep-tools__muted">This scan is admin-launched only. It never suspends or deletes users automatically. Risk findings are added to the review queue.</p>
        {{#if @controller.data}}
          <div class="dep-tools__grid">
            <div class="dep-tools__item"><div class="dep-tools__label">Eligible users</div><div class="dep-tools__value">{{@controller.data.scan_estimate.users}}</div></div>
            <div class="dep-tools__item"><div class="dep-tools__label">Status</div><div class="dep-tools__value">{{@controller.data.scan.status}}</div></div>
            <div class="dep-tools__item"><div class="dep-tools__label">Processed</div><div class="dep-tools__value">{{@controller.data.scan.processed}} / {{@controller.data.scan.total}}</div></div>
            <div class="dep-tools__item"><div class="dep-tools__label">Flagged</div><div class="dep-tools__value">{{@controller.data.scan.flagged}}</div></div>
            <div class="dep-tools__item"><div class="dep-tools__label">API remaining</div><div class="dep-tools__value">{{@controller.data.quota.rate_limit_remaining}}</div></div>
            <div class="dep-tools__item"><div class="dep-tools__label">Last error</div><div class="dep-tools__value">{{@controller.data.scan.last_error}}</div></div>
          </div>
          <div class="dep-tools__actions" style="margin-top: .8rem;">
            <select value={{@controller.scanMode}} {{on "change" @controller.changeScanMode}} aria-label="Existing-user scan mode">
              <option value="domain_only">Domain only - maximum privacy</option>
              <option value="trusted_providers">Full email only for alias-sensitive trusted providers</option>
              <option value="all">Full email for all users</option>
            </select>
            <button class="btn btn-primary" type="button" {{on "click" @controller.startScan}} disabled={{@controller.isScanning}}>{{i18n "admin.disify_email_protection.tools.start_scan"}}</button>
            {{#if (eq @controller.data.scan.status "paused")}}
              <button class="btn" type="button" {{on "click" @controller.resumeScan}} disabled={{@controller.isScanning}}>{{i18n "admin.disify_email_protection.tools.resume_scan"}}</button>
            {{/if}}
          </div>
        {{/if}}
      </section>

      <section class="dep-tools__panel">
        <h2>Policy exceptions</h2>
        <p class="dep-tools__muted">Domain exceptions store the domain. Email exceptions are converted to a non-reversible HMAC before storage.</p>
        <div class="dep-tools__form dep-tools__form--three">
          <select value={{@controller.exceptionKind}} {{on "change" @controller.changeExceptionKind}} aria-label="Exception type">
            <option value="allow_domain">Allow domain</option>
            <option value="block_domain">Block domain</option>
            <option value="allow_email">Allow email</option>
            <option value="block_email">Block email</option>
          </select>
          <input type="text" value={{@controller.exceptionValue}} {{on "input" @controller.updateExceptionValue}} placeholder="example.com or member@example.com" autocomplete="off" />
          <input type="text" value={{@controller.exceptionReason}} {{on "input" @controller.updateExceptionReason}} placeholder="Optional reason" />
          <button class="btn btn-primary" type="button" {{on "click" @controller.addException}} disabled={{@controller.isSavingException}}>{{i18n "admin.disify_email_protection.tools.add_exception"}}</button>
        </div>
        {{#if @controller.data.exceptions.length}}
          <div style="overflow-x: auto;">
            <table class="dep-tools__exceptions">
              <thead><tr><th>Type</th><th>Value</th><th>Reason</th><th>Expires</th><th></th></tr></thead>
              <tbody>
                {{#each @controller.data.exceptions as |item|}}
                  <tr>
                    <td>{{item.kind}}</td><td>{{item.value}}</td><td>{{item.reason}}</td><td>{{item.expires_at}}</td>
                    <td><button class="btn btn-small btn-danger" type="button" {{on "click" (fn @controller.deleteException item)}}>{{i18n "admin.disify_email_protection.tools.delete_exception"}}</button></td>
                  </tr>
                {{/each}}
              </tbody>
            </table>
          </div>
        {{/if}}
      </section>
    </div>
  </template>
);

import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import RouteTemplate from "ember-route-template";
import getURL from "discourse/lib/get-url";
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
      .dep-tools__form { display: grid; grid-template-columns: minmax(18rem, 1fr) auto; gap: .75rem; margin-top: .8rem; align-items: center; }
      .dep-tools__form--scan { grid-template-columns: minmax(24rem, 32rem) auto auto; }
      .dep-tools__form--three { grid-template-columns: minmax(14rem, 1.1fr) minmax(24rem, 2fr) minmax(16rem, 1.2fr) auto; }
      .dep-tools__control,
      .dep-tools__button,
      .dep-tools input,
      .dep-tools select,
      .dep-tools button { box-sizing: border-box; }
      .dep-tools__control { width: 100%; min-height: 2.75rem; padding: .55rem .75rem; }
      .dep-tools select.dep-tools__control { padding-right: 2.25rem; }
      .dep-tools__button { min-height: 2.75rem; white-space: nowrap; }
      .dep-tools__result, .dep-tools__scan { margin-top: .8rem; padding: .8rem; border-radius: 12px; background: var(--primary-very-low); overflow-wrap: anywhere; }
      .dep-tools__grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: .7rem; }
      .dep-tools__item { padding: .7rem; border-radius: 12px; background: var(--primary-very-low); }
      .dep-tools__label { color: var(--primary-medium); font-size: var(--font-down-1); font-weight: 700; }
      .dep-tools__value { margin-top: .2rem; font-weight: 600; overflow-wrap: anywhere; }
      .dep-tools__exceptions { margin-top: .8rem; width: 100%; border-collapse: collapse; }
      .dep-tools__exceptions th, .dep-tools__exceptions td { padding: .5rem .6rem; border-bottom: 1px solid var(--primary-low); text-align: left; vertical-align: top; }
      .dep-tools__toolbar { display: flex; justify-content: space-between; gap: .75rem; align-items: flex-start; margin-bottom: .8rem; }
      .dep-tools__status-note { margin-top: .8rem; }
      @media (max-width: 980px) { .dep-tools__form--scan { grid-template-columns: 1fr 1fr; } .dep-tools__form--three { grid-template-columns: 1fr 1fr; } .dep-tools__grid { grid-template-columns: 1fr 1fr; } }
      @media (max-width: 700px) { .dep-tools__hero { flex-direction: column; } .dep-tools__toolbar { flex-direction: column; } .dep-tools__form, .dep-tools__form--scan, .dep-tools__form--three, .dep-tools__grid { grid-template-columns: 1fr; } }
    </style>
    <div class="dep-tools">
      <section class="dep-tools__hero">
        <div class="dep-tools__copy">
          <h1>{{i18n "admin.disify_email_protection.tools.title"}}</h1>
          <p class="dep-tools__muted">{{i18n "admin.disify_email_protection.tools.description"}}</p>
        </div>
        <div class="dep-tools__actions">
          <a class="btn" href={{overviewUrl}}>{{i18n "admin.disify_email_protection.tools.back"}}</a>
          <a class="btn" href={{reviewUrl}}>{{i18n "admin.disify_email_protection.review.short_title"}}</a>
        </div>
      </section>

      <section class="dep-tools__panel">
        <h2>{{i18n "admin.disify_email_protection.tools.manual_check_title"}}</h2>
        <p class="dep-tools__muted">{{i18n "admin.disify_email_protection.tools.manual_check_description"}}</p>
        <div class="dep-tools__form">
          <input class="dep-tools__control" type="email" value={{@controller.email}} {{on "input" @controller.updateEmail}} placeholder={{i18n "admin.disify_email_protection.tools.manual_check_placeholder"}} autocomplete="off" />
          <button class="btn btn-primary dep-tools__button" type="button" {{on "click" @controller.checkEmail}} disabled={{@controller.isChecking}}>{{i18n "admin.disify_email_protection.tools.check"}}</button>
        </div>
        {{#if @controller.checkResult}}
          <div class="dep-tools__result">
            <strong>{{i18n "admin.disify_email_protection.tools.result_decision"}}:</strong> {{@controller.checkResult.result.decision}}<br />
            <strong>{{i18n "admin.disify_email_protection.tools.result_reason"}}:</strong> {{@controller.checkResult.result.reason}}<br />
            <strong>{{i18n "admin.disify_email_protection.tools.result_domain"}}:</strong> {{@controller.checkResult.domain}}<br />
            <strong>{{i18n "admin.disify_email_protection.tools.result_confidence"}}:</strong> {{@controller.checkResult.result.confidence}}<br />
            <strong>{{i18n "admin.disify_email_protection.tools.result_signals"}}:</strong> {{@controller.checkResult.result.signals}}<br />
            {{#if @controller.checkResult.pending_review}}
              <strong>{{i18n "admin.disify_email_protection.tools.result_pending_review"}}:</strong> #{{@controller.checkResult.pending_review.id}}
            {{/if}}
          </div>
        {{/if}}
      </section>

      <section class="dep-tools__panel">
        <h2>{{i18n "admin.disify_email_protection.tools.scan_title"}}</h2>
        <p class="dep-tools__muted">{{i18n "admin.disify_email_protection.tools.scan_description"}}</p>
        {{#if @controller.data}}
          <div class="dep-tools__grid">
            <div class="dep-tools__item"><div class="dep-tools__label">{{i18n "admin.disify_email_protection.tools.scan_eligible_users"}}</div><div class="dep-tools__value">{{@controller.data.scan_estimate.users}}</div></div>
            <div class="dep-tools__item"><div class="dep-tools__label">{{i18n "admin.disify_email_protection.tools.scan_status"}}</div><div class="dep-tools__value">{{@controller.data.scan.status}}</div></div>
            <div class="dep-tools__item"><div class="dep-tools__label">{{i18n "admin.disify_email_protection.tools.scan_processed"}}</div><div class="dep-tools__value">{{@controller.data.scan.processed}} / {{@controller.data.scan.total}}</div></div>
            <div class="dep-tools__item"><div class="dep-tools__label">{{i18n "admin.disify_email_protection.tools.scan_flagged"}}</div><div class="dep-tools__value">{{@controller.data.scan.flagged}}</div></div>
            <div class="dep-tools__item"><div class="dep-tools__label">{{i18n "admin.disify_email_protection.tools.scan_api_remaining"}}</div><div class="dep-tools__value">{{@controller.data.quota.rate_limit_remaining}}</div></div>
            <div class="dep-tools__item"><div class="dep-tools__label">{{i18n "admin.disify_email_protection.tools.scan_last_error"}}</div><div class="dep-tools__value">{{@controller.data.scan.last_error}}</div></div>
          </div>
          <div class="dep-tools__form dep-tools__form--scan">
            <select class="dep-tools__control" value={{@controller.scanMode}} {{on "change" @controller.changeScanMode}} aria-label={{i18n "admin.disify_email_protection.tools.scan_mode_label"}}>
              <option value="domain_only">{{i18n "admin.disify_email_protection.tools.scan_mode_domain_only"}}</option>
              <option value="trusted_providers">{{i18n "admin.disify_email_protection.tools.scan_mode_trusted_providers"}}</option>
              <option value="all">{{i18n "admin.disify_email_protection.tools.scan_mode_all"}}</option>
            </select>
            <button class="btn btn-primary dep-tools__button" type="button" {{on "click" @controller.startScan}} disabled={{@controller.startScanDisabled}}>{{i18n "admin.disify_email_protection.tools.start_scan"}}</button>
            {{#if @controller.showResumeScan}}
              <button class="btn dep-tools__button" type="button" {{on "click" @controller.resumeScan}} disabled={{@controller.isScanning}}>{{i18n "admin.disify_email_protection.tools.resume_scan"}}</button>
            {{/if}}
          </div>
          {{#if @controller.scanStatusMessage}}
            <p class="dep-tools__muted dep-tools__status-note">{{@controller.scanStatusMessage}}</p>
          {{/if}}
        {{/if}}
      </section>

      <section class="dep-tools__panel">
        <h2>{{i18n "admin.disify_email_protection.tools.exceptions_title"}}</h2>
        <p class="dep-tools__muted">{{i18n "admin.disify_email_protection.tools.exceptions_description"}}</p>
        <div class="dep-tools__form dep-tools__form--three">
          <select class="dep-tools__control" value={{@controller.exceptionKind}} {{on "change" @controller.changeExceptionKind}} aria-label={{i18n "admin.disify_email_protection.tools.exception_type_label"}}>
            <option value="allow_domain">{{i18n "admin.disify_email_protection.tools.exception_kind_allow_domain"}}</option>
            <option value="block_domain">{{i18n "admin.disify_email_protection.tools.exception_kind_block_domain"}}</option>
            <option value="allow_email">{{i18n "admin.disify_email_protection.tools.exception_kind_allow_email"}}</option>
            <option value="block_email">{{i18n "admin.disify_email_protection.tools.exception_kind_block_email"}}</option>
          </select>
          <input class="dep-tools__control" type="text" value={{@controller.exceptionValue}} {{on "input" @controller.updateExceptionValue}} placeholder={{i18n "admin.disify_email_protection.tools.exception_value_placeholder"}} autocomplete="off" />
          <input class="dep-tools__control" type="text" value={{@controller.exceptionReason}} {{on "input" @controller.updateExceptionReason}} placeholder={{i18n "admin.disify_email_protection.tools.exception_reason_placeholder"}} />
          <button class="btn btn-primary dep-tools__button" type="button" {{on "click" @controller.addException}} disabled={{@controller.isSavingException}}>{{i18n "admin.disify_email_protection.tools.add_exception"}}</button>
        </div>
        {{#if @controller.data.exceptions.length}}
          <div style="overflow-x: auto;">
            <table class="dep-tools__exceptions">
              <thead><tr><th>{{i18n "admin.disify_email_protection.tools.exceptions_table_type"}}</th><th>{{i18n "admin.disify_email_protection.tools.exceptions_table_value"}}</th><th>{{i18n "admin.disify_email_protection.tools.exceptions_table_reason"}}</th><th>{{i18n "admin.disify_email_protection.tools.exceptions_table_expires"}}</th><th></th></tr></thead>
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

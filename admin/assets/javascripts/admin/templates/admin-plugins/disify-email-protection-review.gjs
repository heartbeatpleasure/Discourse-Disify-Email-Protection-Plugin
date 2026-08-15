import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import RouteTemplate from "ember-route-template";
import getURL from "discourse/lib/get-url";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

const overviewUrl = getURL("/admin/plugins/disify-email-protection");
const toolsUrl = getURL("/admin/plugins/disify-email-protection-tools");

export default RouteTemplate(
  <template>
    <style>
      .dep-review {
        --dep-surface: var(--secondary);
        --dep-surface-alt: var(--primary-very-low);
        --dep-border: var(--primary-low);
        --dep-muted: var(--primary-medium);
        display: flex;
        flex-direction: column;
        gap: 1rem;
      }
      .dep-review h1, .dep-review h2, .dep-review p { margin: 0; }
      .dep-review__hero, .dep-review__panel {
        min-width: 0;
        padding: 1.2rem 1.35rem;
        border: 1px solid var(--dep-border);
        border-radius: 18px;
        background: var(--dep-surface);
        box-shadow: 0 1px 2px rgb(0 0 0 / 3%);
      }
      .dep-review__hero {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: 1rem;
      }
      .dep-review__copy {
        display: flex;
        min-width: 0;
        flex: 1 1 auto;
        flex-direction: column;
        gap: .35rem;
      }
      .dep-review__muted { color: var(--dep-muted); }
      .dep-review__actions {
        display: flex;
        flex: 0 0 auto;
        flex-wrap: nowrap;
        align-items: center;
        justify-content: flex-end;
        gap: .5rem;
        margin-left: auto;
      }
      .dep-review__actions .btn { white-space: nowrap; }
      .dep-review__toolbar { display: flex; justify-content: space-between; align-items: flex-end; gap: 1rem; }
      .dep-review__control {
        width: min(18rem, 100%);
        min-height: 42px;
        padding: 0 .85rem;
        border: 1px solid var(--dep-border);
        border-radius: 12px;
        background: var(--dep-surface-alt);
        box-sizing: border-box;
      }
      .dep-review__table-wrap { overflow-x: auto; }
      .dep-review table { width: 100%; border-collapse: collapse; }
      .dep-review th, .dep-review td { padding: .55rem .65rem; border-bottom: 1px solid var(--dep-border); text-align: left; vertical-align: top; }
      .dep-review__signals { max-width: 24rem; overflow-wrap: anywhere; color: var(--dep-muted); }
      .dep-review__pager { display: flex; justify-content: space-between; gap: .5rem; margin-top: .8rem; align-items: center; }
      @media (max-width: 900px) {
        .dep-review__hero { flex-direction: column; }
        .dep-review__actions { align-self: flex-end; flex-wrap: wrap; margin-left: 0; }
      }
      @media (max-width: 700px) {
        .dep-review__toolbar { flex-direction: column; align-items: stretch; }
        .dep-review__control { align-self: flex-end; }
        .dep-review__pager { flex-direction: column; align-items: stretch; }
      }
    </style>
    <div class="dep-review">
      <section class="dep-review__hero">
        <div class="dep-review__copy">
          <h1>{{i18n "admin.disify_email_protection.review.title"}}</h1>
          <p class="dep-review__muted">{{i18n "admin.disify_email_protection.review.description"}}</p>
        </div>
        <div class="dep-review__actions">
          <a class="btn" href={{overviewUrl}}>{{i18n "admin.disify_email_protection.review.back"}}</a>
          <a class="btn" href={{toolsUrl}}>{{i18n "admin.disify_email_protection.tools.short_title"}}</a>
        </div>
      </section>

      <section class="dep-review__panel">
        <div class="dep-review__toolbar">
          <div class="dep-review__copy">
            <h2>{{i18n "admin.disify_email_protection.review.filter_title"}}</h2>
            <p class="dep-review__muted">{{i18n "admin.disify_email_protection.review.filter_description"}}</p>
          </div>
          <select class="dep-review__control" value={{@controller.state}} {{on "change" @controller.changeState}} aria-label={{i18n "admin.disify_email_protection.review.filter_label"}}>
            <option value="pending">{{i18n "admin.disify_email_protection.review.state_pending"}}</option>
            <option value="approved">{{i18n "admin.disify_email_protection.review.state_approved"}}</option>
            <option value="rejected">{{i18n "admin.disify_email_protection.review.state_rejected"}}</option>
            <option value="expired">{{i18n "admin.disify_email_protection.review.state_expired"}}</option>
          </select>
        </div>
      </section>

      <section class="dep-review__panel dep-review__table-wrap">
        {{#if @controller.data.items.length}}
          <table>
            <thead><tr><th>{{i18n "admin.disify_email_protection.review.col_created"}}</th><th>{{i18n "admin.disify_email_protection.review.col_user"}}</th><th>{{i18n "admin.disify_email_protection.review.col_domain"}}</th><th>{{i18n "admin.disify_email_protection.review.col_reason"}}</th><th>{{i18n "admin.disify_email_protection.review.col_confidence"}}</th><th>{{i18n "admin.disify_email_protection.review.col_signals"}}</th><th>{{i18n "admin.disify_email_protection.review.col_state"}}</th><th>{{i18n "admin.disify_email_protection.review.col_actions"}}</th></tr></thead>
            <tbody>
              {{#each @controller.data.items as |item|}}
                <tr>
                  <td>{{item.created_at_display}}</td>
                  <td>{{#if item.user}}{{item.user.username}}{{else}}{{i18n "admin.disify_email_protection.review.anonymous_signup"}}{{/if}}</td>
                  <td>{{item.email_domain}}</td>
                  <td>{{item.reason}}</td>
                  <td>{{item.confidence}}</td>
                  <td class="dep-review__signals">{{item.signals}}</td>
                  <td>{{item.state}}</td>
                  <td>
                    {{#if (eq item.state "pending")}}
                      <div class="dep-review__actions">
                        <button class="btn btn-primary btn-small" type="button" {{on "click" (fn @controller.approve item)}}>{{i18n "admin.disify_email_protection.review.approve"}}</button>
                        <button class="btn btn-danger btn-small" type="button" {{on "click" (fn @controller.reject item)}}>{{i18n "admin.disify_email_protection.review.reject"}}</button>
                        {{#if item.user}}
                          <button class="btn btn-small" type="button" {{on "click" (fn @controller.recheck item)}}>{{i18n "admin.disify_email_protection.review.recheck"}}</button>
                        {{/if}}
                      </div>
                    {{/if}}
                  </td>
                </tr>
              {{/each}}
            </tbody>
          </table>
          <div class="dep-review__pager">
            <button class="btn" type="button" {{on "click" @controller.previousPage}}>{{i18n "admin.disify_email_protection.review.previous"}}</button>
            <span>{{i18n "admin.disify_email_protection.review.page_summary" page=@controller.page total=@controller.data.total}}</span>
            <button class="btn" type="button" {{on "click" @controller.nextPage}}>{{i18n "admin.disify_email_protection.review.next"}}</button>
          </div>
        {{else}}
          <p class="dep-review__muted">{{i18n "admin.disify_email_protection.review.empty"}}</p>
        {{/if}}
      </section>
    </div>
  </template>
);

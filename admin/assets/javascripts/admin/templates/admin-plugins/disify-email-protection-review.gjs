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
      .dep-review { display: grid; gap: 1rem; }
      .dep-review h1, .dep-review p { margin: 0; }
      .dep-review__hero, .dep-review__panel { padding: 1rem 1.15rem; border: 1px solid var(--primary-low); border-radius: 16px; background: var(--secondary); }
      .dep-review__hero { display: flex; justify-content: space-between; align-items: flex-start; gap: 1rem; }
      .dep-review__copy { display: grid; gap: .35rem; }
      .dep-review__muted { color: var(--primary-medium); }
      .dep-review__actions { display: flex; flex-wrap: wrap; gap: .45rem; align-items: center; }
      .dep-review__table-wrap { overflow-x: auto; }
      .dep-review table { width: 100%; border-collapse: collapse; }
      .dep-review th, .dep-review td { padding: .55rem .65rem; border-bottom: 1px solid var(--primary-low); text-align: left; vertical-align: top; }
      .dep-review__signals { max-width: 24rem; overflow-wrap: anywhere; color: var(--primary-medium); }
      .dep-review__pager { display: flex; justify-content: space-between; gap: .5rem; margin-top: .8rem; }
      @media (max-width: 650px) { .dep-review__hero { flex-direction: column; } }
    </style>
    <div class="dep-review">
      <section class="dep-review__hero">
        <div class="dep-review__copy">
          <h1>{{i18n "admin.disify_email_protection.review.title"}}</h1>
          <p class="dep-review__muted">{{i18n "admin.disify_email_protection.review.description"}}</p>
        </div>
        <div class="dep-review__actions">
          <select value={{@controller.state}} {{on "change" @controller.changeState}} aria-label="Review state">
            <option value="pending">Pending</option>
            <option value="approved">Approved</option>
            <option value="rejected">Rejected</option>
            <option value="expired">Expired</option>
          </select>
          <a class="btn" href={{toolsUrl}}>Tools</a>
          <a class="btn" href={{overviewUrl}}>{{i18n "admin.disify_email_protection.review.back"}}</a>
        </div>
      </section>

      <section class="dep-review__panel dep-review__table-wrap">
        {{#if @controller.data.items.length}}
          <table>
            <thead><tr><th>Created</th><th>User</th><th>Domain</th><th>Reason</th><th>Confidence</th><th>Signals</th><th>State</th><th>Actions</th></tr></thead>
            <tbody>
              {{#each @controller.data.items as |item|}}
                <tr>
                  <td>{{item.created_at}}</td>
                  <td>{{#if item.user}}{{item.user.username}}{{else}}Anonymous signup{{/if}}</td>
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
            <button class="btn" type="button" {{on "click" @controller.previousPage}}>Previous</button>
            <span>Page {{@controller.page}} - {{@controller.data.total}} items</span>
            <button class="btn" type="button" {{on "click" @controller.nextPage}}>Next</button>
          </div>
        {{else}}
          <p class="dep-review__muted">No review items match the selected state.</p>
        {{/if}}
      </section>
    </div>
  </template>
);

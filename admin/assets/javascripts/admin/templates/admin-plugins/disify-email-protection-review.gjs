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
      .dep-review h1, .dep-review h2, .dep-review h3, .dep-review p { margin: 0; }
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
      .dep-review__actions,
      .dep-review__card-actions {
        display: flex;
        flex: 0 0 auto;
        flex-wrap: wrap;
        align-items: center;
        justify-content: flex-end;
        gap: .5rem;
      }
      .dep-review__actions {
        flex-wrap: nowrap;
        margin-left: auto;
      }
      .dep-review__actions .btn,
      .dep-review__card-actions .btn { white-space: nowrap; }
      .dep-review__toolbar {
        display: flex;
        justify-content: space-between;
        align-items: flex-end;
        gap: 1rem;
      }
      .dep-review__control {
        width: min(18rem, 100%);
        min-height: 42px;
        padding: 0 .85rem;
        border: 1px solid var(--dep-border);
        border-radius: 12px;
        background: var(--dep-surface-alt);
        box-sizing: border-box;
      }
      .dep-review__list {
        display: flex;
        flex-direction: column;
        gap: .8rem;
      }
      .dep-review__card {
        min-width: 0;
        padding: 1rem;
        border: 1px solid var(--dep-border);
        border-radius: 14px;
        background: var(--dep-surface-alt);
      }
      .dep-review__card-header {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: 1rem;
      }
      .dep-review__identity {
        display: flex;
        min-width: 0;
        flex: 1 1 auto;
        flex-direction: column;
        gap: .18rem;
      }
      .dep-review__user {
        display: inline-block;
        width: fit-content;
        max-width: 100%;
        color: var(--primary);
        font-size: var(--font-up-1);
        font-weight: 700;
        line-height: 1.25;
        overflow-wrap: anywhere;
        text-decoration: none;
      }
      a.dep-review__user:hover,
      a.dep-review__user:focus-visible,
      .dep-review__resolution a:hover,
      .dep-review__resolution a:focus-visible {
        color: var(--tertiary);
        text-decoration: underline;
      }
      .dep-review__domain {
        color: var(--dep-muted);
        font-size: var(--font-down-1);
        overflow-wrap: anywhere;
      }
      .dep-review__badges {
        display: flex;
        flex: 0 0 auto;
        flex-wrap: wrap;
        justify-content: flex-end;
        gap: .4rem;
      }
      .dep-review__badge {
        display: inline-flex;
        align-items: center;
        min-height: 28px;
        padding: .25rem .55rem;
        border: 1px solid var(--dep-border);
        border-radius: 999px;
        background: var(--secondary);
        font-size: var(--font-down-1);
        font-weight: 700;
        white-space: nowrap;
      }
      .dep-review__meta {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: .6rem;
        margin-top: .85rem;
      }
      .dep-review__meta-item {
        min-width: 0;
        padding: .65rem .7rem;
        border-radius: 10px;
        background: var(--secondary);
      }
      .dep-review__meta-label {
        color: var(--dep-muted);
        font-size: var(--font-down-1);
        font-weight: 700;
      }
      .dep-review__meta-value {
        margin-top: .18rem;
        font-weight: 600;
        overflow-wrap: anywhere;
      }
      .dep-review__date { white-space: nowrap; }
      .dep-review__signals {
        margin-top: .8rem;
        padding-top: .8rem;
        border-top: 1px solid var(--dep-border);
      }
      .dep-review__signals-list {
        display: flex;
        flex-wrap: wrap;
        gap: .4rem;
        margin-top: .4rem;
      }
      .dep-review__signal {
        display: inline-flex;
        align-items: center;
        min-height: 28px;
        padding: .22rem .5rem;
        border: 1px solid var(--dep-border);
        border-radius: 8px;
        background: var(--secondary);
        font-family: var(--font-family-monospace);
        font-size: var(--font-down-1);
        overflow-wrap: anywhere;
      }
      .dep-review__card-footer {
        display: flex;
        align-items: flex-end;
        justify-content: space-between;
        gap: 1rem;
        margin-top: .85rem;
        padding-top: .85rem;
        border-top: 1px solid var(--dep-border);
      }
      .dep-review__resolution {
        min-width: 0;
        color: var(--dep-muted);
        font-size: var(--font-down-1);
        line-height: 1.45;
      }
      .dep-review__pager {
        display: flex;
        justify-content: space-between;
        gap: .75rem;
        margin-top: 1rem;
        align-items: center;
      }
      @media (max-width: 900px) {
        .dep-review__hero { flex-direction: column; }
        .dep-review__actions { align-self: flex-end; flex-wrap: wrap; margin-left: 0; }
        .dep-review__meta { grid-template-columns: 1fr 1fr; }
      }
      @media (max-width: 700px) {
        .dep-review__toolbar,
        .dep-review__card-header,
        .dep-review__card-footer { flex-direction: column; align-items: stretch; }
        .dep-review__control { width: 100%; }
        .dep-review__badges, .dep-review__card-actions { justify-content: flex-start; }
        .dep-review__meta { grid-template-columns: 1fr; }
        .dep-review__date { white-space: normal; }
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
          <button class="btn" type="button" {{on "click" @controller.loadReview}} disabled={{@controller.isLoading}}>
            {{i18n "admin.disify_email_protection.review.refresh"}}
          </button>
        </div>
      </section>

      <section class="dep-review__panel">
        <div class="dep-review__toolbar">
          <div class="dep-review__copy">
            <h2>{{i18n "admin.disify_email_protection.review.filter_title"}}</h2>
            <p class="dep-review__muted">{{i18n "admin.disify_email_protection.review.filter_description"}}</p>
          </div>
          <select class="dep-review__control" value={{@controller.state}} {{on "change" @controller.changeState}} aria-label={{i18n "admin.disify_email_protection.review.filter_label"}} disabled={{@controller.isLoading}}>
            <option value="pending">{{i18n "admin.disify_email_protection.review.state_pending"}}</option>
            <option value="approved">{{i18n "admin.disify_email_protection.review.state_approved"}}</option>
            <option value="rejected">{{i18n "admin.disify_email_protection.review.state_rejected"}}</option>
            <option value="expired">{{i18n "admin.disify_email_protection.review.state_expired"}}</option>
          </select>
        </div>
      </section>

      <section class="dep-review__panel">
        {{#if @controller.data.items.length}}
          <div class="dep-review__list">
            {{#each @controller.data.items as |item|}}
              <article class="dep-review__card">
                <div class="dep-review__card-header">
                  <div class="dep-review__identity">
                    {{#if item.user}}
                      <a class="dep-review__user" href={{item.user_url}}>{{item.user.username}}</a>
                    {{else}}
                      <span class="dep-review__user">{{i18n "admin.disify_email_protection.review.anonymous_signup"}}</span>
                    {{/if}}
                    <span class="dep-review__domain">{{item.email_domain}}</span>
                  </div>
                  <div class="dep-review__badges">
                    <span class="dep-review__badge">{{item.state_label}}</span>
                    <span class="dep-review__badge">{{i18n "admin.disify_email_protection.review.confidence_badge" value=item.confidence_display}}</span>
                  </div>
                </div>

                <div class="dep-review__meta">
                  <div class="dep-review__meta-item">
                    <div class="dep-review__meta-label">{{i18n "admin.disify_email_protection.review.col_created"}}</div>
                    <div class="dep-review__meta-value dep-review__date">{{item.created_at_display}}</div>
                  </div>
                  <div class="dep-review__meta-item">
                    <div class="dep-review__meta-label">{{i18n "admin.disify_email_protection.review.col_reason"}}</div>
                    <div class="dep-review__meta-value">{{item.reason_label}}</div>
                  </div>
                  <div class="dep-review__meta-item">
                    <div class="dep-review__meta-label">{{i18n "admin.disify_email_protection.review.detected_during"}}</div>
                    <div class="dep-review__meta-value">{{item.flow_label}}</div>
                  </div>
                </div>

                <div class="dep-review__signals">
                  <div class="dep-review__meta-label">{{i18n "admin.disify_email_protection.review.col_signals"}}</div>
                  {{#if item.signals_display.length}}
                    <div class="dep-review__signals-list">
                      {{#each item.signals_display as |signal|}}
                        <span class="dep-review__signal" title={{signal.raw}}>{{signal.label}}</span>
                      {{/each}}
                    </div>
                  {{else}}
                    <div class="dep-review__meta-value">—</div>
                  {{/if}}
                </div>

                <div class="dep-review__card-footer">
                  <div class="dep-review__resolution">
                    {{#unless (eq item.state "pending")}}
                      <div>
                        {{i18n "admin.disify_email_protection.review.resolved_at"}}:
                        <strong>{{item.resolved_at_display}}</strong>
                      </div>
                      {{#if item.resolution_label}}
                        <div>
                          {{i18n "admin.disify_email_protection.review.resolution"}}:
                          <strong>{{item.resolution_label}}</strong>
                        </div>
                      {{/if}}
                      {{#if item.resolved_by}}
                        <div>
                          {{i18n "admin.disify_email_protection.review.resolved_by"}}:
                          <a href={{item.resolved_by_url}}><strong>{{item.resolved_by.username}}</strong></a>
                        </div>
                      {{/if}}
                    {{/unless}}
                  </div>

                  {{#if (eq item.state "pending")}}
                    <div class="dep-review__card-actions">
                      <button class="btn btn-primary" type="button" disabled={{@controller.workingId}} {{on "click" (fn @controller.approve item)}}>{{i18n "admin.disify_email_protection.review.approve"}}</button>
                      <button class="btn" type="button" disabled={{@controller.workingId}} {{on "click" (fn @controller.approvePermanently item)}}>{{i18n "admin.disify_email_protection.review.approve_permanent"}}</button>
                      <button class="btn btn-danger" type="button" disabled={{@controller.workingId}} {{on "click" (fn @controller.reject item)}}>{{i18n "admin.disify_email_protection.review.reject"}}</button>
                      {{#if item.user}}
                        <button class="btn" type="button" disabled={{@controller.workingId}} {{on "click" (fn @controller.recheck item)}}>{{i18n "admin.disify_email_protection.review.recheck"}}</button>
                      {{/if}}
                    </div>
                  {{/if}}
                </div>
              </article>
            {{/each}}
          </div>

          <div class="dep-review__pager">
            <button class="btn" type="button" disabled={{@controller.previousPageDisabled}} {{on "click" @controller.previousPage}}>{{i18n "admin.disify_email_protection.review.previous"}}</button>
            <span>{{i18n "admin.disify_email_protection.review.page_summary" page=@controller.page total=@controller.data.total}}</span>
            <button class="btn" type="button" disabled={{@controller.nextPageDisabled}} {{on "click" @controller.nextPage}}>{{i18n "admin.disify_email_protection.review.next"}}</button>
          </div>
        {{else}}
          <p class="dep-review__muted">{{i18n "admin.disify_email_protection.review.empty"}}</p>
        {{/if}}
      </section>
    </div>
  </template>
);

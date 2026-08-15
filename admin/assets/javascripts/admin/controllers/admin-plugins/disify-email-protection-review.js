import Controller from "@ember/controller";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { tracked } from "@glimmer/tracking";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

export default class AdminPluginsDisifyEmailProtectionReviewController extends Controller {
  @service toasts;

  @tracked data;
  @tracked state = "pending";
  @tracked page = 1;
  @tracked isLoading = false;
  @tracked workingId;

  resetState() {
    this.data = undefined;
    this.state = "pending";
    this.page = 1;
    this.isLoading = false;
    this.workingId = undefined;
  }

  @action
  async loadReview() {
    this.isLoading = true;
    try {
      const query = new URLSearchParams({
        state: this.state,
        page: String(this.page),
      });
      this.data = await ajax(
        `/admin/plugins/disify-email-protection/review.json?${query}`
      );
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isLoading = false;
    }
  }

  @action
  changeState(event) {
    this.state = event.target.value;
    this.page = 1;
    this.loadReview();
  }

  async perform(item, action, successMessageKey) {
    this.workingId = item.id;
    try {
      await ajax(
        `/admin/plugins/disify-email-protection/review/${item.id}/${action}.json`,
        { type: "POST" }
      );
      await this.loadReview();
      this.toasts.success({ data: { message: i18n(successMessageKey) } });
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.workingId = undefined;
    }
  }

  @action
  approve(item) {
    return this.perform(item, "approve", "admin.disify_email_protection.review.approve_success");
  }

  @action
  reject(item) {
    return this.perform(item, "reject", "admin.disify_email_protection.review.reject_success");
  }

  @action
  recheck(item) {
    return this.perform(item, "recheck", "admin.disify_email_protection.review.recheck_success");
  }

  @action
  previousPage() {
    if (this.page <= 1) {
      return;
    }
    this.page -= 1;
    this.loadReview();
  }

  @action
  nextPage() {
    if (!this.data || this.page * this.data.per_page >= this.data.total) {
      return;
    }
    this.page += 1;
    this.loadReview();
  }
}

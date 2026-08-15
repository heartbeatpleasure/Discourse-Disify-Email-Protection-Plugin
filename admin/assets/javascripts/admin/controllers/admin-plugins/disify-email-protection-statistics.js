import Controller from "@ember/controller";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default class AdminPluginsDisifyEmailProtectionStatisticsController extends Controller {
  @tracked data;
  @tracked period = "30";
  @tracked isLoading = false;

  resetState() {
    this.data = undefined;
    this.period = "30";
    this.isLoading = false;
  }

  @action
  async loadStatistics() {
    this.isLoading = true;
    try {
      this.data = await ajax(
        `/admin/plugins/disify-email-protection/statistics.json?period=${this.period}`
      );
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isLoading = false;
    }
  }

  @action
  changePeriod(event) {
    this.period = event.target.value;
    this.loadStatistics();
  }
}

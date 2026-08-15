import DiscourseRoute from "discourse/routes/discourse";
import { i18n } from "discourse-i18n";

export default class AdminPluginsDisifyEmailProtectionReviewRoute extends DiscourseRoute {
  titleToken() {
    return i18n("admin.disify_email_protection.review.title");
  }

  setupController(controller) {
    super.setupController(...arguments);
    controller.resetState?.();
    controller.loadReview?.();
  }
}

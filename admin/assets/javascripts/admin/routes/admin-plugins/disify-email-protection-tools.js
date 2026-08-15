import DiscourseRoute from "discourse/routes/discourse";
import { i18n } from "discourse-i18n";

export default class AdminPluginsDisifyEmailProtectionToolsRoute extends DiscourseRoute {
  titleToken() {
    return i18n("admin.disify_email_protection.tools.title");
  }

  setupController(controller) {
    super.setupController(...arguments);
    controller.resetState?.();
    controller.loadTools?.();
  }
}

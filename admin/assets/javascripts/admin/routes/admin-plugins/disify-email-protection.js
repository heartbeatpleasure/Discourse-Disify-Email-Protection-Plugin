import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";
import { i18n } from "discourse-i18n";

export default class AdminPluginsDisifyEmailProtectionRoute extends DiscourseRoute {
  model() {
    return ajax("/admin/plugins/disify-email-protection/overview.json");
  }

  titleToken() {
    return i18n("admin.disify_email_protection.title");
  }
}

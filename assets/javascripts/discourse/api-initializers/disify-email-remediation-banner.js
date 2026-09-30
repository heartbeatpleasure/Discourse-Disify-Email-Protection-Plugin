import { apiInitializer } from "discourse/lib/api";
import getURL from "discourse/lib/get-url";
import { i18n } from "discourse-i18n";

export default apiInitializer((api) => {
  const currentUser = api.getCurrentUser();
  const remediation = currentUser?.disify_email_remediation;

  if (
    !currentUser ||
    !remediation?.show_banner ||
    remediation.state !== "required"
  ) {
    return;
  }

  const deadline = remediation.enforce_at
    ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(
        new Date(remediation.enforce_at)
      )
    : "";
  const emailUrl = getURL(
    `/u/${encodeURIComponent(currentUser.username)}/preferences/email`
  );
  const key = remediation.restricted
    ? "disify_email_protection.remediation_banner.restricted"
    : remediation.overdue
      ? "disify_email_protection.remediation_banner.overdue"
      : "disify_email_protection.remediation_banner.required";

  api.addGlobalNotice("", "disify-email-remediation", {
    html: i18n(key, { deadline, emailUrl }),
    level: remediation.restricted ? "error" : "warning",
    dismissable: false,
  });
});

import User from "discourse/models/user";
import { i18n } from "discourse-i18n";

export function formatDisifyDate(value) {
  if (!value) {
    return "—";
  }

  const parsed = moment(value);
  if (!parsed.isValid()) {
    return value;
  }

  const configuredTimezone = User.current()?.user_option?.timezone;
  const timezone =
    configuredTimezone && moment.tz.zone(configuredTimezone)
      ? configuredTimezone
      : moment.tz.guess();

  return parsed.tz(timezone).format(i18n("dates.long_with_year"));
}

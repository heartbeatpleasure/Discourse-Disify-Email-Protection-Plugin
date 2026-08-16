import User from "discourse/models/user";

function browserLocales() {
  const languages = globalThis.navigator?.languages;
  if (Array.isArray(languages) && languages.length > 0) {
    return languages;
  }

  const language = globalThis.navigator?.language;
  return language ? [language] : undefined;
}

function userTimezone() {
  const configuredTimezone = User.current()?.user_option?.timezone;
  if (configuredTimezone && moment.tz.zone(configuredTimezone)) {
    return configuredTimezone;
  }

  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || moment.tz.guess();
  } catch {
    return moment.tz.guess();
  }
}

export function formatDisifyDate(value) {
  if (!value) {
    return "—";
  }

  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    return value;
  }

  const timezone = userTimezone();

  try {
    return new Intl.DateTimeFormat(browserLocales(), {
      timeZone: timezone,
      year: "numeric",
      month: "short",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    }).format(parsed);
  } catch {
    const fallback = moment(value);
    if (!fallback.isValid()) {
      return value;
    }

    return fallback.tz(timezone).format("D MMM YYYY, HH:mm");
  }
}

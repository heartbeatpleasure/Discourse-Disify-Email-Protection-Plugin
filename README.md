# Discourse Disify Email Protection Plugin

Adds server-side disposable-email and deliverability protection to Discourse using DISIFY.

## Core behavior

- Disabled by default.
- Monitor, review, and enforce modes.
- Authoritative server-side validation at the `UserEmail` model layer.
- Existing Discourse email syntax, allowed/blocked-domain, screened-email, and uniqueness rules remain in place and run before the external risk check.
- High-confidence disposable-email detection with a conservative default confidence threshold of 90.
- Optional blocking of domains without valid MX records.
- Role-address detection is monitor-only by default.
- Fail-open behavior with a Redis-backed circuit breaker so an external outage does not automatically become a registration outage.
- Privacy-conscious caches and event records; plugin tables do not store raw email addresses.
- Optional Discourse User Notes integration for meaningful existing-user events.
- Optional daily staff-group digest; no per-attempt moderator notifications by default.
- Admin pages for Health, Statistics, Review Queue, and Tools.
- Admin-only manual email checks and controlled existing-user scans.
- Existing-user scans never suspend, delete, silence, or otherwise modify accounts automatically.

## Settings

Open **Admin > Plugins > Disposable Email Protection** and choose **Open settings** or the **Settings** card. Both use the stable setting-key prefix:

`/admin/site_settings/category/all_results?filter=disify_email_protection`

The plugin also corrects its Settings control on the Installed Plugins page to the same URL, matching the settings-navigation pattern used by the administration interface.

All plugin settings use the `disify_email_protection_` prefix, so the filter returns the complete plugin configuration.

## Registration and email changes

The security decision is enforced when a `UserEmail` is validated for persistence. This is intentionally the authoritative integration point. The plugin does not replace the Discourse `UsersController` email-availability endpoint, which reduces coupling to a controller that may change independently of the email model. A failed external check follows the configured fail-open policy; a policy block is returned as a normal email validation error.

## Existing-user scan

The scan is manual only. The default scan mode sends domains rather than complete email addresses. Alias-sensitive trusted providers can optionally be checked with full email addresses, and an explicit all-address mode is available behind an administrator confirmation. Scans are rate-limit aware, resumable, cache domain results, and pause before advancing the cursor when DISIFY becomes unavailable or rate limited.

## Production rollout

1. Install with `disify_email_protection_enabled` disabled.
2. Open Health and run the service test.
3. Configure an API key for production use.
4. Enable the plugin in **Monitor** mode.
5. Review Health, Statistics, and any existing-user scan results.
6. Move to **Review** or **Enforce** only after the site-specific results are understood.

Disabling `disify_email_protection_enabled` immediately removes the additional email validation without requiring a rebuild.

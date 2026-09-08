# Security boundaries

These controls are part of the application contract, not optional UI behavior.

## Browser origins

- `CRM_UI_ORIGINS` (or the legacy singular `CRM_UI_ORIGIN`) is the exact
  allowlist for credentialed CRM and customer-portal API and Action Cable
  requests. Multiple origins are comma-separated; production must include both
  `https://crm.projectred.ca` and `https://portal.projectred.ca`.
- `PUBLIC_SITE_ORIGINS`/`PUBLIC_SITE_ORIGIN` may access only
  `/api/v1/public/*`, with no credentials. A public origin must never be added
  to the credentialed CRM resource rule.
- Origins must be `http` or `https` origins without a path, query, fragment,
  user-info, or wildcard. Production defaults to both final UI origins when the
  CRM setting is omitted; production does not invent a public-site origin.
- The credentialed CRM and portal surfaces use separate encrypted, HttpOnly
  session-cookie keys selected only from those allowlisted origins. Do not
  collapse them back to one cookie: users may be signed in as staff in CRM and
  as customers in the portal in the same browser.
- The temporary `sslip.io` CRM and portal origins and the final DNS origins can
  coexist during a migration. Remove the temporary values only after the UI has
  moved to the final API origin.

## Files and media

- Listing media, board attachments, and chat attachments have separate storage
  boundaries. Board/chat serializers expose only authorized API-relative
  preview/download paths; storage keys are never browser data.
- Previews are authorized and streamed by the API. Downloads may use a
  short-lived signed URL only after authorization. UI code must use the shared
  media URL helpers.
- Upload MIME types are detected with Marcel and are limited to supported media,
  document, archive, and plain-text types. SVG and HTML are not accepted as
  stored attachments. Legacy unsafe media is forced to download disposition,
  never inline execution.
- Storage failures are logged server-side with a generic client error. Raw
  filesystem/S3 error messages must not be returned in JSON or persisted as
  attachment metadata.

## Authentication and payments

- Sign-in is throttled independently by IP and a hashed email key; do not raise
  the general API limit as a substitute for credential-guessing protection.
- Aryeo credentials are Rails-encrypted. Payment provider payloads are reduced
  to non-sensitive reconciliation fields; card/payment-method objects are not
  persisted or serialized to clients.
- Stripe webhook signatures are verified and each provider event ID is stored
  with a unique constraint before processing. Replayed events are ignored, and
  payment success notifications are emitted only on the first state transition.
- Payment provider IDs are internal reconciliation data and are not returned
  to client portal/order consumers.

# Delivery and property sites

## Media asset records

`MediaAsset` represents a file intended for a listing. It stores the storage
key, filename, content type, file dimensions, duration, metadata, media kind,
and processing status.

Kinds:

- `final`: customer deliverables.
- `raw`: internal production media.
- `marketing`: campaign or promotional media.

Statuses:

- `pending`, `processing`, `ready`, and `failed`.

Only `final` + `ready` media is exposed to clients and public property sites.
When `MEDIA_CDN_URL` is configured, the API serializes a CloudFront URL from a
record's storage key. It does not manufacture a CDN URL when the setting is
absent.

## Current local workflow

The internal portal uploads a final asset using an authenticated multipart
endpoint. Rails writes it under `storage/deliveries/organizations/...`, creates
a `pending` media record, and queues `MediaAssets::VerifyUploadJob` on the
`media` Resque queue. The job verifies the file exists and changes the record to
`ready` or `failed`. Ready assets can be opened through an authorized local
download endpoint and are visible in the customer portal.

The following are still required before production media delivery is complete:

1. Direct organization/listing-scoped S3 upload URLs so large files bypass the
   Rails process.
2. Browser upload progress and completion confirmation.
3. A worker that probes/transcodes media and writes image/video variants.
4. CloudFront cache invalidation/versioned keys where transformed files change.

## Board attachment delivery

Board attachments use a separate private storage boundary from listing delivery
media. The API serializes `preview_path` and `download_path` as authorized
`/api/v1/workflow_tasks/.../attachments/...` routes and never exposes a board
storage key as a browser URL.

Preview requests are authorized by Rails and stream from the API origin. Do not
change previews back to a raw S3 or CloudFront URL: credentialed `<img>` and
`<video>` requests can follow an API redirect to another origin and then fail
against the bucket's CORS policy. Downloads may use a short-lived S3 URL after
the same authorization check.

The portal must resolve the returned paths through its shared `apiUrl`/
`mediaAssetUrl` helpers. Never use `preview_path` or `download_path` directly
as a relative URL from the CRM UI origin. If the temporary `sslip.io` hosts are
used, the UI build-time `NEXT_PUBLIC_CRM_API_URL` and API `CRM_UI_ORIGINS` must
refer to the matching temporary API and CRM hosts; restore the real DNS names
only together.

## Chat attachment delivery

Chat files use a separate private bucket (`PROJECT_RED_CHAT_MEDIA_BUCKET`) or
the local `storage/chat_media` directory. Chat serializers return only
authorized API-relative `preview_path` and `download_path` values. The storage
key is never a browser URL, and chat previews must not be changed to raw S3 or
CloudFront URLs: the API origin is the authorization and streaming boundary.

The UI renders chat files with the same `mediaAssetUrl`,
`mediaAssetDownloadUrl`, and `apiMediaNeedsCredentials` contract used by board
attachments. If a new chat surface is added, it must render the serialized
attachment list and use the shared helpers rather than reconstructing paths.

## Property sites

A listing can have one `PropertySite` with a slug and publishing status. The
public API path is:

`GET /api/v1/public/property_sites/:organization_slug/:slug`

It returns the published listing identity, property-site settings, and only the
final ready delivery assets. Rendering the branded public property website is a
future marketing-site responsibility.

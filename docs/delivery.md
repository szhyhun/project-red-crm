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

## Property sites

A listing can have one `PropertySite` with a slug and publishing status. The
public API path is:

`GET /api/v1/public/property_sites/:organization_slug/:slug`

It returns the published listing identity, property-site settings, and only the
final ready delivery assets. Rendering the branded public property website is a
future marketing-site responsibility.

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

## Current workflow

The internal portal can register a final asset that is already stored in the
configured delivery store. That creates the CRM record and makes a ready final
visible in the client portal and, once published, the public property-site API.

This is deliberately not presented as a full uploader. The following are still
required before production media delivery is complete:

1. A server endpoint that issues organization/listing-scoped direct S3 upload
   URLs.
2. Browser upload progress and completion confirmation.
3. A Resque job that probes/transcodes media, writes variants, and changes the
   media status from `pending` to `ready` or `failed`.
4. CloudFront cache invalidation/versioned keys where transformed files change.

## Property sites

A listing can have one `PropertySite` with a slug and publishing status. The
public API path is:

`GET /api/v1/public/property_sites/:organization_slug/:slug`

It returns the published listing identity, property-site settings, and only the
final ready delivery assets. Rendering the branded public property website is a
future marketing-site responsibility.

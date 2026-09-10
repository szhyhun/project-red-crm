# Aryeo Migration

The Aryeo integration is a manual, organization-level historical import. An organization admin opens **Team & access > Organization settings > Manage integrations**, saves an Aryeo API key, validates it, then explicitly queues an import.

## Safety

- The key is encrypted in the ProjectRed database with Rails Active Record Encryption.
- It is never returned by the API, logged, stored in source control, or placed in organization settings.
- The Aryeo client permits only `GET` requests. It rejects every other HTTP method before any network request is made.
- Disconnecting deletes only the local encrypted key. Imported ProjectRed records and Aryeo history remain untouched.
- Imported payment history is sanitized before storage. Card numbers, CVC/CVV values, payment tokens, bank details, routing numbers, account numbers, and secrets are redacted.

## Imported data

The importer upserts readable Aryeo staff, clients, customer teams, catalog products and variants, listings, nested property-site/media metadata, orders/items, safe payment metadata, appointments, and tasks. Each record is marked `origin: aryeo`. Every source object is also retained in `external_records` with its Aryeo ID, sanitized payload, import-run link, and any unsupported endpoint coverage result.

## Normalized catalog and order contract

The imported catalog is converted into the same relational model used by new
ProjectRed orders. An imported product is a reusable `Product`; each Aryeo
variant becomes a `ProductVariant` with its external ID, price in cents,
duration, and square-footage range. An order item is linked to both rows when
Aryeo returns `product_variant_id` or the expanded `product` and
`product_variant` objects. The source item remains in the sanitized snapshot,
but the CRM no longer has to guess a service from a display title.

The importer requests Aryeo's expanded order relationships (`items`,
`listing`, `customer`, and appointments) and explicitly requests listing media
(`images`, `files`, `videos`, `floor_plans`, and interactive content). This is
important: a default collection response is not treated as complete just
because the order or listing row itself exists. The API's documented order
item shape includes a `product_variant_id`, `unit_price_amount`, and nested
product/variant data; those fields are the source of truth for the local
relationships and prices.

Aryeo product payloads can describe a main product or an add-on. A product is
treated as a package when Aryeo explicitly identifies it as a package/bundle
or supplies component/included-service data. Only explicit component
relationships create `ProductComponent` rows; a title that happens to contain
the word “package” never invents included services. A package component always
references the reusable service `Product`, never a price tier. Standalone
services and package services therefore use the same `OrderItem` and
`OrderDeliverable` path after import.

If a selected order or listing contains an expanded customer, listing,
product, or package service that was not selected as a top-level resource, the
importer brings that record in as a dependency. This prevents orders from
silently landing under the placeholder imported client or losing their
catalog links merely because the user selected a narrower resource group.

Existing raw `customer_teams` external records can be mapped once with
`bin/rails customer_teams:backfill`. The task is idempotent and deliberately
keeps `ClientAccount#brokerage_name` in place until customer-facing screens are
migrated to read teams directly.

## Import controls and conflicts

Every import run selects its own resource groups: team users, clients, customer teams, products, listings, orders, appointments, and tasks. Listings, orders, and appointments can optionally be limited to an inclusive **from** and/or **to** date. ProjectRed intentionally fetches the selected date-sensitive collections without relying on provider-side date filters, then applies the range locally to the timestamps returned by Aryeo. Listings use `updated_at` then `created_at`; orders use the earliest nested appointment start, then their appointment/order timestamps; appointments use their start time, then their created/updated timestamp. A record with no usable timestamp is kept rather than silently discarded and is reported as `date_unavailable` in endpoint coverage. Other selected resources always import in full.

Listing collection requests explicitly expand `images`, `files`, `videos`, `floor_plans`, `interactive_content`, `property_website`, and `orders.appointments` using Aryeo's [resource expansion](https://docs.aryeo.com/docs/3-expanding-resources) support. This is required because media and related order data are not guaranteed to be present in the default listing response. The client also accepts Aryeo collection responses represented as arrays, a single object, or a named collection nested inside `data`; a hash response must never be passed through `Array(...)` because Ruby would iterate its key/value pairs and silently drop the listing. If listings are selected without separately selecting clients, customer teams, orders, or appointments, related records embedded in the selected listings are imported as dependencies. Their endpoint coverage is reported as `imported_as_dependency`.

The API contract is `import_start_date` and `import_end_date` in `YYYY-MM-DD` form. Either bound may be omitted, but an end date cannot precede a start date. Aryeo's endpoint references for [appointments](https://docs.aryeo.com/api/aryeo/appointments/get-appointments) and [orders](https://docs.aryeo.com/api/aryeo/orders/get-orders) may document provider-side filters, but ProjectRed does not depend on them; local filtering is the source of truth.

Every run also records one of two policies for records already imported from the same Aryeo ID:

- **Skip existing imported data** is the default. The existing ProjectRed copy remains unchanged and the run reports how many records were skipped.
- **Overwrite the existing imported copy** refreshes that previously imported ProjectRed record from Aryeo.

Neither policy touches native ProjectRed records. The importer does not delete ProjectRed records.

After a catalog/import schema change, use **Overwrite the existing imported
copy** for the affected resource groups. **Skip existing imported data** is a
deliberate no-op for an existing external ID; it is useful for incremental
imports but cannot repair an earlier legacy mapping. A successful overwrite is
safe to repeat because external IDs and order-item IDs are upserted, package
components are synchronized only when the source supplies component data, and
the same source payload remains attached to its `ExternalRecord`.

Do not use `db:reset` or a broad production delete to repair an import. First
run a scoped import with overwrite, review the run's endpoint coverage and
counts, and verify products, variants, customer teams, listings, orders, and
media in the CRM. If a clean re-import is still required for the development
preview environment, take a database snapshot and delete only records owned by
the Aryeo integration for the intended organization through an approved,
scoped maintenance procedure. Native ProjectRed records and unrelated
organizations must remain untouched.

## Media

Remote Aryeo media is imported as pending metadata first, then copied by `AryeoMediaCopyJob`. The importer maps the provider's documented fields instead of assuming one generic URL: photos prefer `original_url` and fall back to `large_url`/`url`, videos use `download_url`, floor plans prefer `original_url` and fall back to `large_url`, and files use `url`. Image/video files returned in the generic files collection are classified into the matching media section from their file type. The asset keeps its provider ID, filename, content type, position, and original source URL in sanitized internal metadata, so a re-import can update the same asset without creating a duplicate.

The copy job downloads the source on the server with the encrypted Aryeo API key when the host is an Aryeo media host. It validates every HTTPS hop, allows only public addresses, follows a small bounded number of redirects, and never forwards the bearer token to a different host. It writes the response to the configured ProjectRed delivery storage with the returned content type. The source URL is never constructed in a React component or exposed as a raw private storage URL; the UI receives the normal authorized API-relative media paths.

If a provider record has no downloadable URL, the importer creates a failed asset and records `completed_with_errors` plus the missing-URL error in the import run. Listing endpoint coverage includes a `media_assets` breakdown (`queued` and `failed`) so an import cannot appear healthy while silently dropping media. If a download or storage write fails, the job retries up to five times, then marks both the external record and asset as failed with the safe error code `media_copy_failed`. A successful later overwrite re-queues the copy and clears the processing error. A green `AryeoImportJob` log only means the import transaction completed; always inspect endpoint coverage, run errors, pending media-copy records, and failed assets before considering listing media available.

For production delivery, set these server-side environment variables:

```sh
PROJECT_RED_MEDIA_BUCKET=project-red-production-media
PROJECT_RED_MEDIA_CDN_URL=https://media.example.com
AWS_REGION=us-west-2
```

When the bucket is configured, copied media is written to S3 under the ProjectRed organization/listing key and serialized with the CDN URL. Without a bucket, development uses `storage/deliveries`.

## Operations

There is no schedule. Starting an import creates an `IntegrationImportRun` and queues `AryeoImportJob` on the `integrations` Resque queue. A Resque worker must be running for the job to begin:

```sh
OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES QUEUE='*' bundle exec rake resque:work
```

The Integration screen refreshes active run status every five seconds and retains the latest ten runs, selected resources, date range, conflict policy, endpoint coverage, counts, partial errors, and terminal failures. The stored connection remains available for a later explicit re-import.

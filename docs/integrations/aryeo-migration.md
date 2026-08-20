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

Existing raw `customer_teams` external records can be mapped once with
`bin/rails customer_teams:backfill`. The task is idempotent and deliberately
keeps `ClientAccount#brokerage_name` in place until customer-facing screens are
migrated to read teams directly.

## Import controls and conflicts

Every import run selects its own resource groups: team users, clients, customer teams, products, listings, orders, appointments, and tasks. Listings can optionally be limited to records **updated on or after** a selected date. The date is applied by ProjectRed after safely reading Aryeo records; it never changes an Aryeo query or record.

Every run also records one of two policies for records already imported from the same Aryeo ID:

- **Skip existing imported data** is the default. The existing ProjectRed copy remains unchanged and the run reports how many records were skipped.
- **Overwrite the existing imported copy** refreshes that previously imported ProjectRed record from Aryeo.

Neither policy touches native ProjectRed records. The importer does not delete ProjectRed records.

## Media

Remote Aryeo media is imported as pending metadata first, then copied by `AryeoMediaCopyJob`. The job retries failed downloads up to five times and records a final error if it cannot complete.

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

The Integration screen refreshes active run status every five seconds and retains the latest ten runs, selected resources, filter date, conflict policy, endpoint coverage, counts, partial errors, and terminal failures. The stored connection remains available for a later explicit re-import.

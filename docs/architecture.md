# ProjectRed CRM Architecture

## Applications

- `projectred.ca`: public website and smart order entry point.
- `app.projectred.ca`: Next.js staff and client portal.
- `api.projectred.ca`: Rails API and source of truth.

## Tenant boundary

One user belongs to one organization. Client accounts, listings, orders, media, invoices, and messages are scoped to that organization. The platform owner is the only cross-organization role.

## Core flows

1. A visitor creates an order draft from the public smart form.
2. A manager confirms or schedules it, and workflow tasks are created from ordered services.
3. Staff upload final delivery assets directly to private S3 storage.
4. Resque jobs process assets and create delivery variants.
5. A manager publishes delivery and sends an invoice or payment link.
6. A client sees only authorized listings, media, invoices, and customer-facing progress.

## Media

S3 stores originals and derivatives. Rails stores only metadata and object keys. CloudFront serves published property-site media publicly and portal delivery media through signed URLs/cookies. Raw footage remains private.

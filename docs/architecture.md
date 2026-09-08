# Architecture

## Application boundaries

`project-red-crm` is a Rails 8 JSON API. It owns ProjectRed organization data,
authorization, operational workflow, catalog pricing, delivery records, and
background-job orchestration.

The other applications have distinct responsibilities:

- `project-red-crm-ui` is one Next.js build with two browser surfaces: the
  staff CRM (`crm.projectred.ca`) and customer portal (`portal.projectred.ca`).
  Local development keeps `http://localhost:3011` as a combined surface and
  also supports `crm.localhost:3011` and `portal.localhost:3011` for boundary
  testing.
- The ProjectRed marketing website is the public sales and ordering entry point.
- PostgreSQL stores durable CRM data.
- Redis and Resque run background work locally and in future deployment.
- S3 and CloudFront are the intended final-delivery media store and CDN.

## API conventions

All application endpoints are under `/api/v1`.

- Authentication uses the Rails session cookie, not browser-held access tokens.
- The CRM and portal share the Rails session and user records, but the UI gates
  each surface by the existing capability set. The hostname is a product
  boundary, not an authorization boundary; API policies remain authoritative.
- `GET /api/v1/auth/csrf` returns the CSRF token required for mutations.
- Browser mutation requests send `X-CSRF-Token` with the session cookie.
- Controllers scope all records through `Current.organization` and Pundit.
- Prices are integers in cents. A product variant, not a browser-provided price,
  is authoritative for an order item.

## Main records

| Record | Purpose |
| --- | --- |
| `Organization` | One media agency workspace and tenant boundary. |
| `User` | Internal staff or a customer user belonging to one organization. |
| `ClientAccount` | Realtor, brokerage, or client entity that owns listings. |
| `Listing` | A property order/workspace. |
| `WorkflowTask` | Internal task with a separate customer-visible flag. |
| `Appointment` | Scheduled listing work. |
| `Product` / `ProductVariant` | Catalog, package, service, and add-on facts with prices. |
| `Tax` / `Coupon` / `TravelFee` | Organization pricing configuration; applying them to an order is a separate workflow. |
| `CustomerTeam` / `PricingPlan` | Brokerage/team relationships and deterministic customer-specific variant price overrides. |
| `Order` / `Invoice` / `Payment` | Commercial record; payment card data is never stored here. |
| `MediaAsset` | A delivery media record pointing to a storage key. |
| `PropertySite` | Published listing landing-page configuration. |
| `Conversation` / `Message` | Organization or listing communication with participant/staff visibility. |

## Background work

Rails uses the Resque Active Job adapter. The current local delivery flow writes
an uploaded file into the local delivery store, then queues a verification job
that marks it ready or failed. Resque Scheduler loads recurring jobs from
`config/resque_schedule.yml` in a separate process, while normal Resque workers
execute the queued jobs. Resque will later also run media transcoding,
catalog imports, notification delivery, and external integrations.

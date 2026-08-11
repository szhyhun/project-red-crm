# Architecture

## Application boundaries

`project-red-crm` is a Rails 8 JSON API. It owns ProjectRed organization data,
authorization, operational workflow, catalog pricing, delivery records, and
background-job orchestration.

The other applications have distinct responsibilities:

- `project-red-crm-ui` is the staff and customer portal on port `3001`.
- The ProjectRed marketing website is the public sales and ordering entry point.
- PostgreSQL stores durable CRM data.
- Redis and Resque run background work locally and in future deployment.
- S3 and CloudFront are the intended final-delivery media store and CDN.

## API conventions

All application endpoints are under `/api/v1`.

- Authentication uses the Rails session cookie, not browser-held access tokens.
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
| `Order` / `Invoice` / `Payment` | Commercial record; payment card data is never stored here. |
| `MediaAsset` | A delivery media record pointing to a storage key. |
| `PropertySite` | Published listing landing-page configuration. |
| `Conversation` / `Message` | Organization or listing communication with participant/staff visibility. |

## Background work

Rails uses the Resque Active Job adapter. Jobs are intended for media
processing, external catalog imports, notification delivery, and future
integration work. The current local delivery flow registers final-media records
after a file has been placed in storage; it does not yet upload or process bytes
through Resque.

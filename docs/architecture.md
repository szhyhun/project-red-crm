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
| `PricingPlan` | Price overrides for a team (`ClientAccount`) or one person (`User`); a person's plan beats their team's. |
| `Order` / `Invoice` / `Payment` | Commercial record; payment card data is never stored here. |
| `ProductComponent` / `OrderDeliverable` | Package composition and production scope; deliverables do not add invoice lines. |
| `MediaAsset` | A delivery media record pointing to a storage key. |
| `MediaReview` / review threads | Customer file-by-file review snapshot and discussion, independent of deliverable lineage. |
| `ClientMembership` | A person's role, status, and account membership within a customer account. |
| `PropertySite` | Published listing landing-page configuration. |
| `Conversation` / `Message` | Organization or listing communication with participant/staff visibility. |

## Background work

Rails uses the Resque Active Job adapter. The current local delivery flow writes
an uploaded file into the local delivery store, then queues a verification job
that marks it ready or failed. Resque Scheduler loads recurring jobs from
`config/resque_schedule.yml` in a separate process, while normal Resque workers
execute the queued jobs. Resque will later also run media transcoding,
catalog imports, notification delivery, and external integrations. The
scheduled Aryeo import watchdog is the recovery boundary for a worker that
dies after dequeuing an import: it turns an abandoned intermediate `running`
record into a terminal `failed` record instead of leaving misleading history.

## Performance and stale-code rules

Read-side API serializers must not issue relation queries inside a collection
loop. A controller either preloads the association or deliberately uses one
scoped query; it then filters, sorts, and groups the loaded records in memory.
Review workspaces batch visible media for all deliverables, and conversation
responses preload message context, attachments, and media references together.
If a serializer is intentionally limited (for example, the latest 20 chat
messages), keep that limit in SQL rather than preloading an unbounded history.

Request-scoped memoization is appropriate for stable, repeated authorization
lookups such as a customer's active membership. It must not be used for data
that can change during a transaction or for private data shared between users.
Cache keys for customer-facing responses must include the organization, user or
account boundary, and the relevant record version; never cache an authorization
decision globally.

When a provider or media contract is shared by more than one surface, its
metadata belongs to the domain model or a dedicated service, not to a
controller. Remove pass-through aliases and compatibility helpers as soon as
their callers are moved to the canonical method. A new abstraction is justified
only when it owns behavior, a query boundary, or an independently testable
business action.

## Business logic and Interactors

Multi-step business workflows use the Interactor boundary documented in
[`docs/interactors.md`](interactors.md). Controllers authorize and call one
action or Organizer; jobs load durable records and call one action or
Organizer; models retain validations, associations, and database invariants.
Actions return a named context with typed failure codes, while Organizers make
the ordered workflow visible and reusable. New automation composition belongs
under `app/interactors/automations/organizers`, and integration-specific actions
belong under `app/interactors/integrations/<provider>/actions`. Provider
transport and grouped payload mapping belong under `app/services/<provider>`;
only meaningful business workflow boundaries are Interactors.

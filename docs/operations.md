# Operations workflow

## Listing lifecycle

A listing is the property-centered workspace for a customer order. Current
statuses are:

`draft`, `quoted`, `booked`, `in_production`, `review`, `delivered`, and
`cancelled`.

Internal users can create a client account and listing, then add tasks,
appointments, staff assignments, catalog items, delivery records, and a
property site from that workspace.

## Tasks and calendar

- `WorkflowTask` tracks title, stage, status, assignee, due date, ordering, and
  whether the task is customer-visible.
- `Appointment` tracks a listing, assigned user, start/end times, notes, and
  status.
- `ListingAssignment` records staff roles such as photographer, videographer,
  editor, or manager.
- Activity events record changes such as listing creation, appointment changes,
  and registered delivery assets.

The portal renders an overview, listings table, weekly production calendar, and
ordered status board. Calendar appointments can be dragged to a new date/time,
edited, reassigned, cancelled, or deleted. The API prevents overlapping active
appointments for one staff member. Board cards can be reordered and moved
between `todo`, `in_progress`, `blocked`, and `done`; details include stage,
priority, assignee, due date, description, and client visibility.

## Catalog, orders, and invoices

Products and variants hold package, service, or add-on prices. Creating an
order resolves product variants on the server, calculates totals in cents, and
does not trust a price sent by the portal.

An invoice can be drafted once for an order. It receives an organization-scoped
number and begins with the order total as its balance due. An internal user can
then send it to the client account's email address and active portal users. The
notification intent is stored before Resque is called, and the invoice is marked
`sent` once that durable intent exists.
Payable invoices create idempotent Stripe PaymentIntents for their server-side
balance. Signed Stripe webhooks reconcile successful payments, reject amount or
currency mismatches, update invoice balances, and enqueue one payment receipt.
Card details go directly from Stripe Payment Element to Stripe and are never
stored by ProjectRed. Refund operations remain future work.

## Invitations

Organization admins can invite internal staff through Devise Invitable. Client
account invitations create a client user invitation and the matching
`ClientMembership`. Invitations use the ProjectRed email layout.

## Customer emails

ProjectRed sends branded email for workspace sign-up, invitations, sent invoices,
successful payments, and a listing's first transition to `delivered`. Welcome,
invoice, payment, and delivery
messages are enqueued on the `mailers` Resque queue. A listing can still be marked
delivered without an email address; a manually sent invoice requires one.

Notification deliveries remain in `notification_deliveries` until successfully
sent. After a Redis outage, enqueue pending and failed records with:

```sh
bundle exec rake notifications:dispatch_pending
```

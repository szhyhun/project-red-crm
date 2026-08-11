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

The portal currently renders an overview, listings table, calendar list, and a
status-based board. It is intentionally a simplified production workflow, not a
ClickUp clone.

## Catalog, orders, and invoices

Products and variants hold package, service, or add-on prices. Creating an
order resolves product variants on the server, calculates totals in cents, and
does not trust a price sent by the portal.

An invoice can be drafted once for an order. It receives an organization-scoped
number and begins with the order total as its balance due. Sending an invoice,
hosted payment links, payment webhooks, taxes, and refunds are not implemented
yet.

## Invitations

Organization admins can invite internal staff through Devise Invitable. Client
account invitations create a client user invitation and the matching
`ClientMembership`. Delivery email configuration is environment-specific and
must be configured before production invitations are relied on.

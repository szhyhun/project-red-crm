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

- `WorkflowTask` belongs to a board and tracks title, status, assignee, due
  date, ordering, and whether the task is customer-visible.
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
between `todo`, `in_progress`, `blocked`, and `done`; details include priority,
assignee, due date, description, and client visibility.

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

## Live chat delivery

Chat messages are persisted first, then `Conversations::NotifyJob` broadcasts a
small per-user notification through Action Cable. The API, Resque worker, and
Action Cable adapter must use the same `REDIS_URL`. The Nginx proxy in front of
the API must also forward WebSocket upgrades on `/cable`:

```nginx
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection $connection_upgrade;
```

If chat messages save but unread badges and open tabs do not update, check the
worker and Redis first, then look for `Failed to upgrade to WebSocket` in the
API journal. That log entry means the proxy dropped the upgrade request; it is
not an application authorization failure.

## Chat retention cleanup

Recurring jobs are registered in `config/resque_schedule.yml` and run by the
long-lived `project-red-crm-scheduler` Resque Scheduler service. The chat
retention entry runs once per day and evaluates each conversation's
`retention_period` (`two_months` by default, or `six_months`, `one_year`, or
`forever`). The cleanup deletes private chat storage before deleting the
matching message and attachment rows, and keeps the conversation itself.

## Private chat media permissions

Chat attachments use the private bucket configured by
`PROJECT_RED_CHAT_MEDIA_BUCKET`; putting that name in `api.env` does not grant
the application access to it. The EC2 runtime role must have
`s3:ListBucket` and `s3:GetBucketLocation` on the bucket ARN, plus
`s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, and
`s3:AbortMultipartUpload` on the bucket's object ARN (`/*`). Update the
`project-red-crm-media` role policy whenever a private media boundary is added
or renamed. Keep these resources separate from the public listing CDN bucket.

Check the scheduler and run a one-off cleanup through the release directory
with:

```sh
sudo systemctl status project-red-crm-scheduler --no-pager
sudo journalctl -u project-red-crm-scheduler -n 100 --no-pager
bundle exec rake conversations:purge_expired
```

Add future recurring jobs to `config/resque_schedule.yml`, then require their
Resque job classes from `lib/tasks/resque_scheduler.rake`. This keeps the
schedule reviewable in source control and ensures workers and the scheduler
load the same Rails/Redis configuration. Resque Scheduler's schedule and
delayed queues can be inspected through a privately authenticated Resque web
surface when that admin surface is enabled; never expose that surface
unauthenticated.

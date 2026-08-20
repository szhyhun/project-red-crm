# ProjectRed CRM API plan

## Scope

This repository owns the API, persistence, permissions, and background work for
ProjectRed. It is a standalone Rails application, not an extension of Aryeo.
Aryeo can be imported while it remains useful, but ProjectRed owns its own
catalog, orders, schedules, delivery, client portal, and operational workflow.

## Boundaries

- `project-red-crm`: Rails API on port `3002`.
- `project-red-crm-ui`: staff and customer portal on port `3001`.
- ProjectRed marketing site: public ordering entry point and property pages.
- PostgreSQL: durable application data.
- Redis + Resque: media processing, imports, notifications, and delivery jobs.
- S3 + CloudFront: final deliverables and property media. Raw footage remains
  outside customer delivery storage unless explicitly retained.

## Delivery phases

1. Tenancy, authentication, roles, catalog, and API conventions.
2. Listings, orders, appointments, assignments, workflow tasks, and activity.
3. Client delivery portal, property websites, media upload/processing, invoices,
   payments, and conversation permissions.
4. Public smart order integration, Aryeo catalog import, deterministic
   recommendations, and external integrations such as Picaivid.

## Rules that do not change

- A user belongs to one organization. Contractors do not share one login across
  agencies.
- Platform owner access is separate from organization roles.
- Pricing is stored in integer cents. Product variant prices are authoritative.
- Aryeo imports update source catalog facts only. Local capability and
  recommendation metadata is never overwritten.
- Payment-card details never enter ProjectRed. Stripe-hosted payment flows own
  card collection.
- Customer-facing progress is intentionally separate from internal tasks.

## Planned operational entities

These records are deliberately deferred from the current core CRM, but are part
of the durable ProjectRed replacement for Aryeo. They must be organization
scoped and use integer cents or basis points for money and rates.

### Catalog and pricing

- `Tax`: named, active organization tax rate with a jurisdiction/custom scope.
- `TravelFee`: flat, percentage, per-kilometre, or per-minute fee. Distance
  rules depend on a staff `HomeBase`.
- `Coupon`: time-bounded, redemption-limited fixed or percentage discount.
- `PricingPlan` and `PricingPlanPrice`: client/team-specific variant prices.
- `ProductFilter`: a saved catalogue filter for future public/private order
  forms; deferred until order forms need it.

Order snapshots already keep calculated tax, fee, and discount cents. These
records configure the calculation; they do not make past orders mutable.

### Payroll and customer credit

- `PayRun`: draft, approved, and paid periods containing `PayrollItem`s.
- Add `pay_run_id` to `PayrollItem` when pay-run approval is implemented.
- `CustomerTeam` and `CustomerTeamMembership`: a real brokerage/team model in
  place of a free-text brokerage name.
- `CreditTransaction`: append-only client credit/debit ledger. Invoice balance
  remains derived from invoices rather than duplicated.

### Scheduling and dispatch

- `BusinessHours`: organization defaults plus optional staff overrides.
- `TwilightWindow`: location/date-aware twilight scheduling rules.
- `CalendarConnection`: encrypted provider credentials and explicit sync
  direction.
- `HomeBase`: staff address and coordinates for routing and distance fees.
- `Territory` and `TerritoryUser`: postal/boundary eligibility for products and
  assignment.
- `BookingLimit`: staff daily and weekly booking capacity.
- `AssignmentPriority`: ordered, explainable dispatch rules.
- `SchedulingSetting`: lead time, buffers, and cancellation window.
- `MileageEntry`: appointment-linked staff travel record.

### Platform records still needed before external scale

- `PaymentProviderConnection` and webhook/event records for Stripe/Square
  credentials, idempotent payment events, refunds, and disputes. Card data is
  never stored locally.
- `Invitation` and notification preferences/templates for staff/customer
  onboarding and operational email/SMS delivery.
- Immutable `AuditEvent` records for administrative changes, exports, access to
  private deliverables, pricing overrides, and billing actions.
- Delivery revision/version records, download-expiry/access policy, and
  watermark/share-link controls for customer-facing media.
- Geocoding/route snapshots and time-zone data on listings/appointments so
  scheduling, travel fees, and calendar exports remain reproducible.

### Later customer-facing products

- `OrderForm`: public, private, or embedded ordering forms with ordered fields
  and settings.
- Reporting, property-site analytics, marketing activity/generation history,
  branded/unbranded property sites, domains, and website editor content remain
  planned later work.

## Local operation

The development stack is PostgreSQL, Redis, Rails, and a Resque worker. Tests
are intentionally not run automatically during visual/product iteration.

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

## Local operation

The development stack is PostgreSQL, Redis, Rails, and a Resque worker. Tests
are intentionally not run automatically during visual/product iteration.

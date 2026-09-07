# ProjectRed CRM documentation

This directory describes the Rails API as it exists locally. It separates
implemented behavior from planned integrations so the team does not mistake a
local vertical slice for a production-ready external integration.

- [Product guide](product-guide.md): plain-language customer-facing features and configuration.
- [Architecture](architecture.md): application boundaries, data ownership, and API conventions.
- [Access model](access-model.md): organization membership and customer-facing authorization rules.
- [Operations](operations.md): listings, tasks, calendar work, catalog orders, and invoice drafts.
- [Delivery](delivery.md): final media records, property sites, and customer delivery visibility.
- [Local development](local-development.md): PostgreSQL, Redis, Resque, Rails, and portal startup.
- [Product plan](plan.md): the staged roadmap, including smart ordering and external integrations.
- [Client portal build plan](client-portal-plan.md): the design briefs read against the schema, the capability authorization model, the multi-board design, the T1–T13 task breakdown, and the B1 board-content follow-up.
- [Marketing module](marketing/plan.md): planned only. Turning delivered media into social posts, schedules, and paid campaigns.

## Current status

The local API supports organization sign-up/sign-in, internal production work,
client accounts, listings, task and appointment assignment, catalog orders,
invoice drafting and sending, asynchronous local final-media uploads, property-site
publishing, conversations with per-conversation retention, staff invitations,
branded lifecycle emails, a restricted customer portal response, and a manual
Aryeo import when configured.

Direct browser-to-S3 uploads, media transcoding, recurring Aryeo sync, Square
payment support, and smart-order recommendations remain planned or deployment-
dependent work.

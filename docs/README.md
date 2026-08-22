# ProjectRed CRM documentation

This directory describes the Rails API as it exists locally. It separates
implemented behavior from planned integrations so the team does not mistake a
local vertical slice for a production-ready external integration.

- [Architecture](architecture.md): application boundaries, data ownership, and API conventions.
- [Access model](access-model.md): organization membership and customer-facing authorization rules.
- [Operations](operations.md): listings, tasks, calendar work, catalog orders, and invoice drafts.
- [Delivery](delivery.md): final media records, property sites, and customer delivery visibility.
- [Local development](local-development.md): PostgreSQL, Redis, Resque, Rails, and portal startup.
- [Product plan](plan.md): the staged roadmap, including smart ordering and external integrations.
- [Marketing module](marketing/plan.md): planned only. Turning delivered media into social posts, schedules, and paid campaigns.

## Current status

The local API supports organization sign-up/sign-in, internal production work,
client accounts, listings, task and appointment assignment, catalog orders,
invoice drafting and sending, asynchronous local final-media uploads, property-site
publishing, conversations, staff invitations, branded lifecycle emails, and a
restricted customer portal response.

Direct browser-to-S3 uploads, media transcoding, Stripe payment links, Aryeo
import, and smart-order recommendations remain planned work.

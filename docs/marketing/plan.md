# Marketing Module

Turning delivered listing media into ready-to-run social posts, schedules, and paid campaigns. One click by default, editable when it matters.

Status: **plan only**. Nothing here is implemented.

## The opening

Dripflow and Rechat both start from a *listing record*. A feed reports that a property went live, and they generate marketing from whatever fields and thumbnails that feed carries. Neither company makes the media.

ProjectRed does. The full-resolution photos, video, floorplan, and property site are in hand at the moment they are produced — days before the listing is public, and at a quality no feed exposes. That drives the central decision:

**Trigger marketing off delivery, not off listing creation.** When an editor marks assets ready, a finished post can be produced immediately — best frames, real floorplan, agent branding — while a feed-driven competitor is still waiting for the portal to publish.

It also fits the existing business. Marketing sells as an add-on product on the order for a shoot, priced per listing, through the catalog that already exists.

## Reference products

### Dripflow — automation-first

Australian, CRM-triggered, deliberately narrow. A listing hits the feed and Dripflow fans out automatically. Their pricing mechanic is worth copying: **one credit activates a listing, which then runs its whole lifecycle** (just listed, open home, under offer, sold) at no further charge.

- Automatic graphics per lifecycle stage
- Automatic property videos — feed and story cuts, with branding and music
- Automatic property micro-sites
- Canvas graphic editor over pre-made templates
- Weekly Schedule Builder using dynamic placeholders
- Auto-boost listings; lead magnet campaigns generated from an uploaded PDF
- Content library, calendar view, RSS article posting, Google review import

### Rechat — suite-first

American, MLS-driven, far broader — a brokerage platform where marketing is one department. The "Studio" is the part worth studying; the rest is a different company than ours.

- Studio: websites, email, social, digital ads, print, CMA
- Direct Instagram publishing with no re-upload step
- AI assistant ("Lucy") that drafts campaigns and builds listing sites on command
- Marketing analytics — deliveries, opens, bounces, clicks
- Brand-consistent templates across a brokerage
- Deals, contracts, DocuSign, compliance checklists

### The read

Build Dripflow's loop, borrow Rechat's Studio, ignore Rechat's scope. Dripflow proves that automation off a trigger is the product. Rechat proves people will pay for an editor once the automation has earned their trust.

## The decision that shapes everything

"One click by default, customizable when needed" sounds like two features. It is one, and it hinges on how templates are represented.

Define a template as a **JSON layer spec** — frames, image slots, text slots, brand tokens — and render that spec with the *same* React component in two places: in the browser for preview and, later, the Studio; and in headless Chromium for the exported PNG or MP4 frame. One spec, two renderers.

- **The Studio comes nearly free.** An editor that manipulates the spec is a different UI over the same renderer, not a second rendering engine.
- **WYSIWYG is structural, not maintained.** Preview and export cannot drift, because they are the same code.
- **Auto-templates are specs with unfilled slots.** A rule picks a template, binds slots to listing data and ranked photos, and renders. Customizing means overriding bound values.
- **Re-rendering is cheap.** Change a brand colour and every asset regenerates from its stored spec — no re-upload, no manual rework.

For video, do not build in-house first. Start on a hosted render API (Creatomate or Shotstack), keep the same spec shape, and move to FFmpeg workers once volume justifies it. Video is where a quarter disappears with nothing shipped.

## Domain model

New entities in the idiom of what already exists. Each hangs off `ClientAccount` or `Listing`.

| Entity | Holds | Notes |
| --- | --- | --- |
| `BrandKit` | Logos light/dark, palette, fonts, headshot, contact block, agency mark, disclaimers | Per `ClientAccount`, with an org-level default. Covers the agent contact / logo / colour requirement. |
| `MarketingTemplate` | `kind` (post/story/carousel/video), `aspect`, `category`, `spec` jsonb, `version` | Versioned, so editing a template never mutates already-published assets. |
| `MarketingAsset` | Listing, brand kit, template, `overrides` jsonb, rendered files, status | Rendered output plus the spec that produced it. Re-renderable. |
| `MarketingPost` | Asset, channel, caption, hashtags, `scheduled_at`, external id, status | One asset can become several posts across channels. |
| `SocialAccount` | Provider, encrypted tokens, page / IG business id, scopes, `expires_at` | Encrypt as `IntegrationConnection#api_key` does. Expiry monitoring is not optional. |
| `MarketingRule` | Trigger event, conditions, template set, schedule offsets, `auto_publish` | The auto-template engine. Fires on delivery, status change, appointment booked. |
| `AdCampaign` | Objective, `daily_budget_cents`, run dates, geo radius, audience jsonb, external ids | Budgets in cents, like every other money column. |
| `AdMetric` | Campaign, date, impressions, clicks, leads, `spend_cents` | Daily rollup on a schedule; powers the upsell loop below. |
| `SchedulePlan` | Weekly slots with placeholder types | Dripflow's Weekly Schedule Builder. Slots resolve against available content at post time. |

One change to existing code: `MediaAsset` needs a **hero score** so a rule can pick the six best frames without a human. Start crude — category, orientation, resolution, editor ordering — and improve later. Category is already derived from content type; this is the same shape of thing.

## Sequencing

Ordered by dependency. The Meta gate in P4 is why organic publishing ships before ads.

### P0 — One post, end to end (~2 weeks)

Brand kit, template spec format, render worker, one "Just listed" template. An agent clicks once on a delivered listing and downloads a 4:5 PNG. Proves the spec and the renderer.

### P1 — Template library and formats (~3 weeks)

- Carousel (multi-slot) and 9:16 story from the same spec
- Lifecycle categories: coming soon, just listed, open house, price change, sold, testimonial
- AI captions from listing facts and brand voice, with hashtag sets
- Bulk download; still no publishing

Useful without any Meta approval.

### P2 — Connect and schedule (~3 weeks)

- Meta OAuth, page and IG business selection, token refresh
- Direct publish to IG feed, story, carousel, and Facebook page
- Calendar and queue; approval step before anything goes out

**Submit the Meta app review on day one of this phase.** It takes 2–4 weeks per submission and runs in parallel with the build.

### P3 — Auto-templates (~2 weeks)

- `MarketingRule` fires on delivery and status change
- Weekly schedule builder with placeholder slots
- Per-agent opt-in: full auto, approve-first, or off

This is the Dripflow loop.

### P4 — Paid campaigns (~4 weeks)

- Boost a post: budget, duration, radius, audience
- Lead ads landing on the property site we already produce
- Leads written back as CRM records; daily spend and result sync

Gated on Meta Advanced Access, which needs API call history that only shipping P2 can accumulate.

### P5 — Studio and video (open)

Drag-and-drop editing of the spec, brand governance for franchises, and automatic property videos through a hosted render API.

## Meta constraints

| Constraint | Detail | Consequence |
| --- | --- | --- |
| App review | Required to publish for accounts we do not own. 2–4 weeks per submission. | Submit at the *start* of P2. |
| Scope creep | Over-requesting permissions is a leading cause of rejection. | Request publishing scopes only; apply for ads scopes separately, later. |
| Advanced Access | Marketing API tier needs at least 1,500 calls in 15 days and an error rate under 15%. | Ads cannot come first. Organic publishing generates the qualifying volume. |
| Publish limits | 100 API-published posts per rolling 24h per account; a carousel counts as one. | Fine per agent; plan queue backoff if an agency shares one account. |
| Token expiry | Long-lived tokens still lapse; users change passwords and revoke apps. | Health check per account, proactive reconnect prompts, visible disconnected state. |

"Ads Management Standard Access" becomes the **Marketing API Access Tier** as of 4 May 2026. Use the current name in any application.

## Beyond Dripflow

Earned by owning production:

- **Best-frame selection** from originals rather than feed thumbnails.
- **Pre-listing teasers.** A booked shoot means a "coming soon" post can run before the listing exists anywhere.
- **Floorplan reveal stories.** We make floorplans; nobody else can animate one.
- **Property site as the ad destination**, with leads landing straight in the CRM.

Earned by owning the CRM:

- **Performance to upsell.** "Video posts outperformed stills 4:1" is an argument for booking video on the next shoot.
- **Approval workflow** before publishing, which agencies require.
- **Brand governance** — franchise-locked elements agents cannot override.
- **Compliance auto-insert** for licence numbers and mandated disclaimers.

## Risks

- **Template design is a design investment, not an engineering one.** Ten excellent templates beat sixty mediocre ones, and this is the most visible part of the product. Budget real design time.
- **Music licensing for video** is a legal question, not a technical one. Dripflow offers music selections because they licensed a library. Resolve before P5.
- **Token disconnection will be the top support ticket.** Design the reconnect flow before launch.
- **Scope drift into a social suite.** RSS articles, review importing, and content libraries are Dripflow features unrelated to our advantage. Resist until the core loop is proven.
- **Render cost and storage.** A dozen assets per listing across formats multiplies the storage bill. Set retention rules early.

## First thing to build

A brand kit, one template spec, one renderer, and one "Just listed" post generated from delivered photos. That exercises the whole architecture — branding, slot binding, photo ranking, rendering — while committing to nothing about publishing, ads, or approvals.

Everything after it repeats a proven shape: more templates, more triggers, more channels.

## Sources

- [dripflow.io/features](https://dripflow.io/features/) — demo and pricing pages were under maintenance when this was written, so pricing beyond the per-listing credit model is unconfirmed
- [rechat.ai](https://rechat.ai/)
- [Meta — Marketing API Access Tier update](https://developers.meta.com/blog/updates-to-ads-management-standard-access-feature/)

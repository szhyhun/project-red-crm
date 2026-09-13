# ProjectRed media workflow and portal UI

This is the canonical product and implementation plan for the media workflow,
staff listing workspace, and customer portal. It is based on the client portal,
team/branding, and media/revision briefs supplied for ProjectRed, including the
attached screenshots. The written brief defines behavior; screenshots define
hierarchy and interaction patterns, not pixel-perfect dimensions.

The board issues that came from the briefs are ordinary, human-readable work
items. Their visible IDs are planning labels only. They are not database
references to this Markdown file, and no runtime record needs an internal plan
field to explain where it came from.

The existing `/api/v1` URL namespace is retained for API compatibility. It is
not a release scope or a promise of a smaller product edition.

## Implementation status

Audited against the code on 2026-09-10 (schema `2026_09_10_110000`, 188 spec
files). **Done** means the schema, API, UI, and specs for that area exist and
were checked; **Partial** lists what is still missing; nothing is marked done
on the strength of a plan alone.

| Area | Status | Outstanding |
| --- | --- | --- |
| Catalog and packages | Done | — |
| Orders and deliverables | Done | — |
| Boards, tasks, and placements | Done | — |
| Board workflows and automations | Done | — |
| Media and storage boundaries | Done | — |
| Catalog interface | Done | — |
| Staff CRM listing workspace | Partial | version history, Download All, Custom Image Sizing, Interactive Floor Plan, poster/duration |
| Customer listing media page | Partial | video poster/duration, floor-plan viewer |
| Change requests | Partial | legacy endpoint remains for older clients; new portal flow uses media reviews |
| Media reviews | Partial | image pins and video timecodes in the interface (the API already stores them) |
| Chat interface | Partial | customer users still auto-joined; no message editing; Escape does not close the thread menu |
| APIs and authorization | Done | — |
| Customer portal shell | Not started | left navigation, account switcher, Book a shoot, Billing |
| Customer accounts, teams, and roles | Not started | all five build steps |

What each row rests on:

- **Catalog and packages** — `products.deliverable_type` and `sla_days`, no
  `sqft` column; `product_components` rejects nested packages, non-package
  parents, and self-inclusion; active square-foot ranges cannot overlap;
  component CRUD API.
- **Orders and deliverables** — `orders.approved_at`; `order_deliverables` with a
  unique `materialization_key`; the idempotent `Orders::Approve` organizer,
  `Orders::ApproveOrder`, and `Orders::DeliverableMaterializer`; `POST
  /orders/:id/approve`; target dates skip weekends.
  Approval enqueues workflows through `Workflows::Trigger`, which is idempotent.
- **Boards, tasks, and placements** — parent tasks, task kinds, and group keys;
  `workflow_task_placements` with a partial unique index allowing one home
  placement per task; `workflow_task_deliverables`; the mover synchronizes
  shared placements and grouped deliverables.
- **Board workflows and automations** — all six tables,
  `Workflows::ExecuteRun` and its action interactors, `Workflows::Trigger`,
  `BoardWorkflowJob`, run history, retry endpoint, and the Board → Workflows
  screen.
- **Media and storage** — `media_assets.order_deliverable_id`, `version`, and
  `superseded_by_id`; upload, link, and reorder endpoints; separate delivery,
  board, and chat storage; `mediaAssetUrl` prefers `cdn_url`. Customer review
  is based on ready, customer-visible listing media and does not require an
  internal order deliverable.
- **Catalog interface** — service and package editors, drag-and-drop component
  order, and the "This range overlaps another active range" message.
- **Staff CRM listing workspace** — hero, Media, Marketing, Orders, Activity, and
  conversation sections, with upload and reorder. Versions are stored and
  covered by specs, but no staff screen shows them yet.
- **Customer listing media page** — one section per service or media kind, the
  "Media will appear when ready" empty state, Download All, accepted-by-default
  state, and review in place: the media page is the review (see Media review UI
  contract). The legacy change-request endpoint stays available for old
  clients, but the portal no longer presents a second standalone request
  composer.
- **Change requests** — the compatibility endpoint still validates listing,
  deliverable, delivered state, and asset ownership, but new portal requests
  use `MediaReview` and its file-specific threads. A submitted change review
  adds one notification to `Conversation.account_thread_for`; the detailed
  review discussion remains outside the chat.
- **Chat interface** — no listing selector in the new-conversation dialog; the
  first conversation is selected; staff team chats keep a saved drag order;
  unread counts; dismissible errors; Escape closes dialogs and the attachment
  viewer. Chat messages cannot be edited, so the rule that attachment deletion
  happens only while editing cannot apply as written; today chat attachments
  cannot be deleted at all. Decide whether to build message editing or amend
  the rule.
- **APIs and authorization** — every endpoint listed below exists, and
  `authorization_coverage_spec` enforces authorization on every controller.
  Customer billing is limited to `User#billing_access?` (admins, platform
  owners, managers): invoices, order and item money, listing payment status,
  and the listings payment filter are withheld from production staff, covered
  by `billing_access_spec`.
- **Customer portal shell** — the portal is still a single page with listings
  above an Updates chat block.
- **Customer accounts, teams, and roles** — `ClientMembership.role` exists but no
  policy reads it; there are no portal team or chat-management endpoints.

Browser smoke checks recorded on 2026-09-10 covered the first review window
(a dialog with a side comment panel). That window has since been replaced by
the review page described below, which has not had a browser check yet.

## Product rules

ProjectRed sells media services to a customer and then tracks the production
work needed to deliver them. A service can be purchased on its own or included
in a package.

```text
Product: Standard Property Photography

ProductVariant: 0–1,000 sqft — $299
ProductVariant: 1,001–2,000 sqft — $399
```

Standalone purchase:

```text
ProductVariant → OrderItem → OrderDeliverable
```

Package purchase:

```text
Package ProductVariant → package OrderItem
                         → ProductComponent
                         → service OrderDeliverable
```

The package is billed once. Its included services create production
deliverables, but they do not create additional invoice lines.

Permanent catalog rules:

- `Product` is the reusable package, service, or add-on.
- `ProductVariant` is a purchasable price and scope option.
- `ProductComponent` references the service `Product`, never a service variant.
- A package may contain service products but may not contain another package.
- A service remains independently sellable through its own variants.
- There is no `Product.sqft` field.
- Authoritative price tiers are relational rows, not a JSON pricing array.
- JSON is reserved for provider payloads, snapshots, and flexible metadata.
- Active square-foot ranges for one product cannot overlap.
- Catalog edits never rewrite historical order prices, scopes, or deliverables.

When a package variant is selected, its scope is copied to every included
deliverable. The component contributes no new charge:

```text
Package selected: 0–1,000 sqft
Photography deliverable: Standard Property Photography
Scope: 0–1,000 sqft
Additional price: $0
```

## Data model

### Catalog

```text
products
  id
  organization_id
  slug
  title
  description
  kind                       package | service | addon
  deliverable_type           photography | video | vertical_reel | drone |
                             floor_plan | tour | property_site | files | other
  sla_days                   business days
  active
  external_source
  external_id
  source_payload             jsonb

product_variants
  id
  product_id
  title
  price_cents
  sqft_min                   nullable
  sqft_max                   nullable
  duration_minutes           nullable
  quantity_label             nullable
  active
  external_id
  source_payload             jsonb

product_components
  id
  organization_id
  package_product_id         → products.id
  service_product_id         → products.id
  quantity
  position
```

`ProductVariant` owns the catalog price that is selected at checkout. An active
customer pricing plan may provide the effective price for that variant. The
`OrderItem` stores the effective historical price, title, quantity, scope, and
snapshot so later pricing-plan or catalog edits cannot change an existing
order.

### Orders and deliverables

```text
orders
  approved_at                nullable datetime

order_deliverables
  id
  organization_id
  listing_id                 nullable → listings.id
  order_id                   → orders.id
  order_item_id              → order_items.id
  product_component_id       nullable → product_components.id
  service_product_id         → products.id
  title
  description
  deliverable_type
  sla_days
  scope_sqft_min             nullable
  scope_sqft_max             nullable
  scope_label                nullable
  status                     not_started | in_progress | in_review | delivered
  target_on                  nullable date
  delivered_at               nullable datetime
  delivery_version           default 0
  position                   default 0
  cancelled_at               nullable datetime
  metadata                   jsonb
  materialization_key        unique
```

Package components and standalone services share this model. An approved
order is materialized by one service and then triggers the configured board
workflow after the transaction commits. Repeating approval is safe: the
materialization key prevents duplicate deliverables, and the workflow run
key prevents duplicate runs for the same order and workflow definition.

`OrderDeliverable` is production state, not billing. It is never included in
invoice totals. A deliverable belongs to its organization, order, order item,
service product, optional package component, and optional listing. Its listing
must agree with the order listing when the order has one.

The customer-facing state is derived from this closed vocabulary. Internal
board columns may have names such as Blocked or Quality Assurance, but those
names never leak into the portal:

```text
not_started → in_progress → in_review → delivered
```

Requesting changes from delivered work returns the deliverable to
`in_progress`. A cancelled deliverable is excluded from active workflow and
portal results; it is not a new customer status.

### Boards, tasks, and placements

```text
boards
  organization_id
  name, slug, description
  kind                       production | internal | custom
  visibility                 organization | restricted
  requires_listing
  client_visible
  archived, position
  created_by_id
  settings                   jsonb

workflow_columns
  board_id
  name, key, color, category, position
  -- key is unique inside one board

workflow_tasks
  organization_id
  board_id
  listing_id                 nullable
  parent_task_id             nullable → workflow_tasks.id
  task_kind                  task | parent | deliverable
  workflow_group_key         nullable, retry/idempotency identity
  title, description, description_html
  status, priority, position
  assignee_id, reporter_id
  customer_visible
  due_at, started_at, completed_at
  metadata                   jsonb

workflow_task_placements
  workflow_task_id
  board_id
  workflow_column_id
  position
  is_home
  -- one placement per task and board; one home placement per task

workflow_task_deliverables
  workflow_task_id
  order_deliverable_id
  position
```

A task has one canonical record and can appear on multiple authorized boards.
The home placement is the canonical production card. Moving a task updates the
selected placement, canonical task status, all shared placements that have a
matching canonical column, linked deliverables, customer status, and activity.
Grouped deliverables stay separate cards in the portal.

Default column mapping:

```text
Todo          → not_started
Active Work   → in_progress
Review        → in_review
Done          → delivered
Blocked       → in_progress
```

Boards that require a property enforce `listing_id` at the model boundary.
Internal boards may contain organization work without a listing. Client-visible
tasks are exposed only from client-visible boards.

## Board workflows and automations

Workflow configuration lives at **Board → ⋯ → Workflows / Automations**. The
interaction follows the useful scoped pattern documented by ClickUp: a named
automation has a trigger, optional conditions, and ordered actions.

```text
board_workflows
  id, organization_id, board_id
  name, description, enabled
  trigger_key                order_approved
  is_default
  workflow_version
  created_by_id

board_workflow_conditions
  board_workflow_id
  field                      deliverable_type |
                             service_product_id |
                             package_product_id
  operator                   equals | not_equals | in
  value                      jsonb
  position

board_workflow_actions
  board_workflow_id
  action_type
  configuration              jsonb
  position

board_workflow_status_mappings
  board_workflow_id
  source_status              not_started | in_progress | in_review | delivered
  target_column_key
  position
```

Supported actions are:

```text
create_parent_task
create_or_group_child_task
place_on_board
link_deliverable
assign_to_user
assign_to_group
```

An active workflow can target only its own organization's board and users. A
status mapping must point to a column on the workflow board. Invalid or missing
mappings prevent a workflow from being configured safely. New workflows and
draft activations must define all four customer-facing status mappings; the
runner falls back to the board's first column only for legacy records that
predate mappings.

Run history is durable and inspectable:

```text
board_workflow_runs
  organization_id, board_workflow_id, order_id
  idempotency_key
  status                     pending | running | succeeded |
                             succeeded_with_warnings | failed
  triggered_at, started_at, completed_at
  retry_count
  error
  metadata                   jsonb

board_workflow_run_steps
  board_workflow_run_id
  board_workflow_action_id
  status                     pending | running | succeeded |
                             skipped | failed
  position
  input, output              jsonb
  error
```

Approval retries do not duplicate deliverables, tasks, placements, or links.
A failed run can be retried from run history; successful runs cannot be
requeued as if they had failed.

## Media and storage boundaries

```text
media_assets
  order_deliverable_id       nullable → order_deliverables.id
  version
  superseded_by_id           nullable → media_assets.id
```

Storage boundaries are explicit:

- final listing/deliverable media uses the configured delivery storage/CDN
  boundary;
- board issue and comment attachments use private board storage;
- chat attachments use private chat storage;
- customer uploads in a change request remain chat attachments;
- existing assets are referenced by ID and are never copied into chat.

Staff can see older media versions. Customers see only ready, final,
customer-visible, non-hidden assets. Every serializer exposes authorized API
relative `preview_path` and `download_path` values. Ready customer-visible
listing media also includes the configured public `cdn_url`. It never exposes
a storage key, private bucket URL, or raw CDN construction to React.

The portal response renders one collapsible card for every active
`OrderDeliverable`. Its title, deliverable type, status, dates, and assets stay
together, so a package's photography, video, floor-plan, and other services do
not become one undifferentiated file list. Older or imported listing files that
still have no `order_deliverable_id` remain visible through
`listing_asset_groups`, with one honest card per media category (`Property
photos`, `Videos`, `Floor plans`, `Tours`, or `Files`). Those compatibility cards
cannot offer deliverable-only change requests. Once the order/import graph is
materialized, assets are linked to their real deliverables and the category
fallback is no longer used for those files.

Preview routes authorize the parent record before streaming. Download routes
may redirect to a short-lived signed URL only after the same authorization
check. UI media tags resolve serialized paths through `apiUrl`,
`mediaAssetUrl`, `mediaAssetDownloadUrl`, and `apiMediaNeedsCredentials`;
`mediaAssetUrl` must prefer `cdn_url` when present. An API preview that
redirects a credentialed browser request to private S3 is not a substitute for
the CDN URL because the final response may not allow the portal origin.

When a new attachment type is added, the change is incomplete until storage,
serializer, API types, URL helpers, renderer, and a negative access-control
spec are updated together. This prevents the repeated raw-path/private-bucket
mistake that caused missing board and chat images.

## Staff CRM listing workspace

The staff page follows the supplied CRM screenshot:

```text
CRM shell
 ├── left navigation and organization/team context
 ├── listing hero
 │    ├── property image
 │    ├── address and city/province
 │    ├── production status
 │    └── staff actions
 ├── Media
 │    └── one compact row per OrderDeliverable
 ├── Marketing
 ├── Orders and services
 └── Activity and account conversation
```

Media is deliverable-first. “Images”, “Videos”, “Floor Plans”, “Tours”, and
“Files” are presentation categories, not replacement database objects. Each
row shows service title, deliverable type, asset count, customer-safe status,
target date, and an expand/collapse control.

Expanded staff controls can include Add/upload, Rearrange by drag and drop,
Custom Image Sizing, Interactive Floor Plan, poster/duration metadata, version
history, individual download, and Download All. These controls operate on
`MediaAsset` records linked to the existing deliverable; uploading never
creates a product, variant, or fake service.

## Customer portal

The portal is a separate audience and host surface, even though local
development can share the Next.js application and Rails session:

```text
portal shell
 ├── header: account switcher (only with 2+ accounts), Book a shoot, user menu
 ├── Listings      needs-attention items sort to the top
 ├── Messages      the chats this person is a member of
 ├── Billing       account admins only
 └── Account       profile; team management for account admins
```

There is no Home or Dashboard page: Listings is the landing page, and anything
waiting on the customer (media to review, feedback requested, a pending
reschedule) sorts to the top of it with a visible marker. There is no Orders
page: for a customer an order and a listing are nearly one-to-one, and what
they need from an order is money, which is Billing. Book a shoot is a primary
action in the header on every page, not a navigation item.

The customer cannot see CRM boards, staff administration, workflow
configuration, internal columns, staff-only processing states, billing
administration, or another customer account.

The canonical listing media route is:

```text
/?view=listing-media&listing=7
```

The page calls:

```http
GET /api/v1/portal/listings/7/media
```

The layout is property-first:

```text
listing media page
 ├── property hero, address, customer-facing status
 ├── delivery summary and Download / Download All
 ├── compact collapsible deliverable cards
 ├── listing/service conversation context
 └── activity and change-request history
```

Cards begin collapsed and remember expansion for the current page session.
Empty cards say “Media will appear when ready.” They do not reserve large
blank regions. A card includes service title or media category, readable
description, status, target/delivered date when known, asset count, and
downloads. **Review media** is shown and enabled whenever any ready,
customer-visible media exists; it is not rendered as a disabled button.

Customer media presentation is type-specific:

- photography: thumbnails, full preview, multi-select, download selected/all;
- video: poster, duration, watch, download;
- floor plan: preview, download, and an interactive viewer when available;
- files: filename, type, size, and download.

There is no customer Add button. A new customer file is sent as a private
conversation attachment.

### Media review semantics

Media review is opt-in. Ready, customer-visible media is customer-delivered as
soon as the upload/processing pipeline succeeds; no separate CRM order
approval or manual “mark deliverable as delivered” action is required. A
listing with customer-visible media but no `MediaReview` record is treated as
implicitly accepted; the system does not create a fake approval row. The
portal shows the media and offers **Review media** whenever there is something
to view.

Viewing media creates nothing. The customer's first comment opens a draft review for the currently published
customer-visible media snapshot. The snapshot may contain assets linked to an
internal `OrderDeliverable` and assets that were uploaded or imported directly
to the listing; resuming a draft adds anything published since. Draft
comments remain private to the customer until the review is submitted. A draft
that is abandoned is not an approval and remains available to resume.

There is at most one open draft per listing and customer account, enforced by
a partial unique index. When a service in an open draft is delivered again,
the draft is retired as `outdated`: its unsent comments stay visible to the
customer, marked as not sent, and the next comment starts a new draft. After a
review is submitted the customer may start another one, as in a merge request.

After submission the discussion stays on the review page. Both sides reply on
the same threads, and replies are published immediately. Either side may
resolve or reopen a thread. Staff never see a draft or its threads.

Submitting an explicit **Approve delivery** creates a `MediaReview` with
`outcome: approve` and `status: approved`. This is distinct from implicit
acceptance because it records that the customer actively reviewed and approved
the files. The other review outcomes are `comment` and `request_changes`.

`request_changes` must carry at least one comment or a summary, so production
is never sent work without knowing what to change. It marks the reviewed
customer media as needing work and adds a production activity/task when an
internal deliverable exists. It still works
for directly uploaded or imported listing media that has no order deliverable.
It does not introduce a separate customer-review status. Review comments stay
attached to their exact asset snapshot, with optional image/PDF coordinates or
video time ranges. Staff responses and replacements are tracked in the review
workspace, while the account conversation receives only a notification and
link to the review.

### Media review data model

The review model is deliberately separate from both the internal
`OrderDeliverable` and the source `MediaAsset`:

```text
media_reviews
------------
id
organization_id
listing_id
client_account_id
created_by_id
submitted_by_id       nullable
number                per listing and customer account
delivery_version      version marker for the customer-visible media snapshot
status                open | submitted | changes_requested | approved | outdated
outcome               nullable: comment | request_changes | approve
summary
summary_html
submitted_at
created_at
updated_at
```

```text
media_review_deliverables
-------------------------
media_review_id
order_deliverable_id
delivery_version
position
```

```text
media_review_assets
-------------------
media_review_id
media_asset_id
order_deliverable_id   nullable
asset_version
filename
content_type
byte_size
position
```

`media_review_assets` is a relational snapshot of the exact files offered to
the customer. Its `order_deliverable_id` is optional: it provides internal
lineage when available but never gates customer review. The join does not copy
the file or store another storage key. The original `MediaAsset` remains the
source of the authorized preview/download path, so storage boundaries and IDOR
checks stay centralized.

The snapshot version uses the highest relevant media/delivery version. A later
replacement or newly published media set can therefore invalidate an older
review without requiring every file to have an order deliverable.

```text
media_review_threads
--------------------
media_review_id
media_review_asset_id  nullable
order_deliverable_id   nullable
created_by_id
resolved_by_id         nullable
status                 open | resolved | outdated
anchor_type            asset | region | timestamp | page
page_number            nullable
time_start_ms          nullable
time_end_ms            nullable
anchor_x/y/width/height nullable
resolved_at            nullable
```

```text
media_review_comments
---------------------
media_review_thread_id
author_id
body
body_html
status                 draft | published
edited_at              nullable
created_at
updated_at
```

One review can contain many threads, and one thread can contain the original
customer comment plus staff replies. Draft comments are visible only to the
customer account while the review is open. Submitting a review publishes all
draft comments in one transaction. No review row is created for an untouched
delivery, which is the database representation of implicit acceptance.

### Media review API

The customer-facing endpoints are:

```http
GET    /api/v1/portal/listings/:listing_id/reviews
POST   /api/v1/portal/listings/:listing_id/reviews
GET    /api/v1/portal/reviews/:id
POST   /api/v1/portal/reviews/:id/threads
POST   /api/v1/portal/review_threads/:id/comments
POST   /api/v1/portal/review_threads/:id/resolve
POST   /api/v1/portal/review_threads/:id/reopen
PATCH  /api/v1/portal/review_comments/:id
DELETE /api/v1/portal/review_comments/:id
POST   /api/v1/portal/reviews/:id/submit
```

`GET .../reviews` returns the review page as `workspace`: delivered services
with their current files, unassigned files grouped by kind, every review round
the viewer may see, and every thread with its comments and capabilities. A
thread follows its file through replacements: `media_asset_id` is the file it
shows on now, `original_media_asset_id` the file that was commented on, and
`outdated` marks the difference. Staff read the same payload from
`GET /api/v1/listings/:listing_id/media_reviews`.

Creating a review resumes the open draft, bringing its snapshot up to date, or
opens a new one; a double submission resolves to the same draft.
`media_review.order_deliverable_ids` remains an optional scoping hint for older
clients. The server always includes ready, current, customer-visible media for
the listing, including assets without an `OrderDeliverable`, and rejects files
that are not ready, current, and customer-visible. A draft whose services were
delivered again is retired rather than resumed.

The thread request is shaped like:

```json
{
  "thread": {
    "media_review_asset_id": 17,
    "anchor_type": "region",
    "anchor_x": 12.5,
    "anchor_y": 24,
    "anchor_width": 18,
    "anchor_height": 10
  },
  "comment": {
    "body": "Please brighten this room.",
    "body_html": "<p>Please brighten this room.</p>"
  }
}
```

A thread may name its file by `media_asset_id` instead of
`media_review_asset_id`. A comment on a whole service, including one with no
files yet, is `{ "order_deliverable_id": 5, "anchor_type": "deliverable" }`.

The submit request is:

```json
{
  "media_review": {
    "outcome": "request_changes",
    "summary": "Please replace the exterior image."
  }
}
```

`approve` records explicit approval and leaves customer media available.
`comment` records a submitted review without changing production state.
`request_changes` creates activity/task work for any linked internal
deliverables, while still notifying staff about unlinked listing media. It adds
one `review_notification` message to the account conversation. The notification
carries `media_review_id` and review context; the review comments themselves
stay in the review workspace.

Staff can read a review through:

```http
GET  /api/v1/media_reviews/:id
POST /api/v1/media_review_threads/:id/comments
POST /api/v1/media_review_threads/:id/resolve
POST /api/v1/media_review_threads/:id/reopen
```

Staff replies are published. Staff can neither see nor reply to a thread while
its review is still a draft, and a thread whose only comment is deleted is
removed rather than left empty. Every route scopes through the
organization and the listing/customer relationship before Pundit authorization
runs. A customer cannot use a review ID, review asset ID, deliverable ID, or
media asset from another account or listing.

### Media review UI contract

Review follows a merge request in one respect above all: discussion lives on
the file it is about, and the same file is never shown twice on a page. There
is no separate review screen or section.

- **Customer.** The listing media page is the review. Each service or media
  kind is a section of thumbnails. Clicking a thumbnail opens the full-size
  viewer; the **+** on a thumbnail starts a comment. A file with discussion is
  outlined, and its threads open as a full-width row directly under it in the
  same grid, so every comment on the listing is readable in one scroll. A
  service can take a comment of its own, which is how to ask for work with no
  file yet.
- **Staff.** The listing workspace's Media section is the review. Cards with
  discussion carry an unresolved or resolved badge, their threads open as a
  full-width row under the card, and a row holding discussion opens by default.
- **Toolbar**, at the top of either: review state, **N unresolved ‹ ›** to
  jump between open threads in page order, **Review history** (one line per
  round, plus threads on files that are no longer delivered), and for the
  customer **Finish review (N pending)**.
- **Threads** show the conversation in order with a Customer or Team badge,
  then **Reply…** and **Resolve thread**. Resolved threads fold to one line.
  Pending comments are marked and visible only to their author until
  **Finish review**, which offers Comment (the default), Approve, or Request
  changes, with an optional summary.
- **Filters** (All, With comments, Unresolved) narrow the customer's grid once
  there is any discussion.

Category groups for imported or directly uploaded files are valid sections;
they do not need to be turned into fake `OrderDeliverable` records.

Media URLs still go through `mediaAssetUrl` and `mediaAssetDownloadUrl`; the
review component never constructs storage URLs.

### Customer accounts, teams, and roles

A customer signs in as a person (`User`) and works inside an account
(`ClientAccount`). There are two kinds of account:

- **Solo** — one person, who is its admin. One solo account per email.
- **Team** — one or more admins plus members. Admins invite and remove users.

A person may hold their own solo account and also be a member of any number of
teams. `ClientMembership.role` is already `admin | member`; finer permissions
are future work.

| | Account admin | Member |
| --- | --- | --- |
| See the account's listings | yes | yes |
| See billing and pay invoices | yes | no |
| Create chats | yes | no |
| Invite account users into a chat | yes | no |
| See chats | all of the account's | only chats they are in |
| Invite, remove, and change roles of account users | yes | no |

Rules:

- An account always keeps at least one active admin.
- With more than one account, an account switcher appears in the header and
  everything — listings, chats, billing — is scoped to the active account.
- Permissions are per account, not per person: someone can be admin of their
  solo account and a member of a team, so Billing appears or disappears as they
  switch. Capabilities are therefore computed for the user in the active
  account, and the navigation is built from them.
- Chats have explicit members; nobody is auto-joined. A new account starts with
  one chat between its admins and organization admins, which the account admin
  grows or splits. Organization admins see every customer chat.
- Existing chats keep their current members. They were auto-joined under the
  old rule, and removing people silently would cut them off from conversations
  they are already in.

The older `CustomerTeam` record, which grouped client accounts, has been
retired: a pricing plan belongs to a team (`ClientAccount`) or to one person,
and Aryeo customer teams import as client accounts holding their people.

Matching Aryeo's customer teams (September 2026) is built as follows:

- **Memberships** carry `invited → active → revoked | archived`, a default
  team per person, and a per-team delivery-email switch that team emails
  honour. Pending invitations can be sent or resent, including to people an
  import created. A customer can join a team with its affiliate code.
- **A team** (`ClientAccount`) carries its identity, an internal note, the
  download lock, price display and reminder settings, a page of totals and
  activity, archive (no new listings or orders) and split.
- **A person** carries phone, license, timezone, social profiles, an internal
  note, blocked-from-ordering, a credit ledger (`CreditTransaction`), and may
  own a pricing plan that beats their team's.
- **Who pays**: a team may name a billing member, who is made and kept an
  admin, receives invoice and payment emails, and is the only customer offered
  online payment; `billing_pays_externally` offers it to nobody.
- **Visibility**: billing, pricing, downloads and marketing templates are each
  hidden, admins-only or everyone. Billing filters invoices today; the other
  three are exposed in the portal payload for screens that do not exist yet.
- **Notifications**: a per-team matrix of events against email, SMS and push.
  Email honours it; SMS and push store the choice.
- **Teams of one** show no team chrome, staff side or portal.

- **Ordering**: an order spends the payer's credit (the billing member's, or
  the ordering customer's) and a team with a billing member, or one paying
  externally, is not asked to pay up front (`Orders::ApplyCustomerTerms`).
- **Chats**: someone who becomes an active admin joins the team's chat;
  members are still added by hand.
- **Price lists**: staff edit a team's and a person's price list from the team
  page and the person's record.

Build order:

1. **Roles and per-account capabilities** — policies read the membership role;
   billing is admin-only; the last admin cannot be removed or demoted.
2. **Team management** — account admins invite, remove, and change roles of
   users from Account → Team.
3. **Chats** — account admins create chats and choose members; the automatic
   account thread and its auto-join are removed; a new account gets its admin
   chat.
4. **Change requests** — sent into a chat the requester chooses.
5. **Portal shell** — left navigation, account switcher, Book a shoot, Messages
   as a full-height single thread, Billing aggregated across listings.

### Legacy change-request compatibility

The original Request Changes endpoint remains available for older clients and
continues to validate listing access, deliverable ownership, delivered state,
and selected media references. The current portal does not use that standalone
composer. Customers use Media review instead, because one review can contain
comments on several files and one clear outcome.

The compatibility request is still stored as a normal conversation message
with structured context:

```text
messages
  listing_id                 nullable
  order_deliverable_id       nullable
  message_kind               message | change_request

message_media_references
  message_id
  media_asset_id
  position
```

Selected delivered assets are referenced by ID. New files use the chat
attachment flow. The server validates listing access, deliverable ownership,
delivered state, asset ownership/readiness/visibility, and customer access.
No separate `revision_requests` table is needed; new work uses the review tables
described above.

## Catalog interface

The catalog distinguishes a reusable service from its variants and package
components.

Service editor:

```text
title, description, deliverable type, SLA
pricing variants table:
  variant name | from sqft | to sqft | price | active
```

Package editor:

```text
package title and description
package pricing variants table
included service products
drag-and-drop component order
quantity
```

Inline validation says “This range overlaps another active range.” The editor
never creates a product per square-foot tier.

## Chat interface

Team chats are always available to staff. Customer chat navigation appears only
when the user is a member of at least one customer conversation. A customer
account can have many conversations, each with explicit members chosen by the
account admin (see Customer accounts, teams, and roles). Messages carry
listing/service context when they concern a property.

The new-conversation dialog has no listing selector and no required first
message. Client-visible conversations select one or more customer accounts and
team participants; internal conversations select team participants only. Customer
users are added by an account admin or by staff, never automatically.

The chat editor and issue comment editor share rich-text behavior:

- attachments with previews, progress, retry, and API-relative media paths;
- safe HTML sanitization and plain-text fallback;
- dismissible upload errors that clear on navigation or a successful action;
- Escape closes dialogs, drawers, menus, and popups;
- the first available conversation is selected on the Messages page;
- customer conversations sort by latest message, while staff team conversations
  keep each user's saved drag-and-drop order;
- unread counts appear in the Messages navigation item and beside each unread
  conversation without changing either ordering rule;
- read-only messages have no separate attachment delete action;
- attachment deletion is available only while editing its message.

Chat attachment deletion removes the attachment with its owning message. It is
not exposed as a standalone destructive action in the normal message view.

## APIs and authorization

Important endpoints:

```http
# Catalog
GET/PATCH /api/v1/products/:id
GET/POST/PATCH/DELETE /api/v1/products/:product_id/components/:id

# Orders and production
POST /api/v1/orders/:id/approve
GET  /api/v1/orders/:id/deliverables
GET  /api/v1/order_deliverables/:id
PATCH /api/v1/order_deliverables/:id

# Portal
GET  /api/v1/portal/listings/:listing_id/media
POST /api/v1/portal/listings/:listing_id/deliverables/:deliverable_id/change_requests
GET/POST /api/v1/portal/listings/:listing_id/reviews
GET    /api/v1/portal/reviews/:id
POST   /api/v1/portal/reviews/:id/threads
POST   /api/v1/portal/review_threads/:id/comments
PATCH/DELETE /api/v1/portal/review_comments/:id
POST   /api/v1/portal/reviews/:id/submit
GET    /api/v1/media_reviews/:id
POST   /api/v1/media_review_threads/:id/comments
POST   /api/v1/media_review_threads/:id/resolve
POST   /api/v1/media_review_threads/:id/reopen

# Board workflows
GET/POST/PATCH/DELETE /api/v1/boards/:board_id/workflows
GET /api/v1/boards/:board_id/workflow_runs
POST /api/v1/boards/:board_id/workflow_runs/:id/retry

# Media
POST /api/v1/media_assets/upload
POST /api/v1/media_assets/link
POST /api/v1/media_assets/reorder
GET  /api/v1/media_assets/:id/preview
GET  /api/v1/media_assets/:id/download

# Conversations
GET/POST /api/v1/conversations
GET/PATCH/DELETE /api/v1/conversations/:id
POST /api/v1/conversations/:id/messages
POST /api/v1/conversations/:conversation_id/messages/:message_id/attachments
```

Staff conversation creation accepts `kind`, `subject`, `member_ids`, and
`client_account_ids`. Internal rooms use only team members. Client-visible
creation creates a new room for the selected customer account and includes only
the account users chosen for it; nobody is added automatically. Account admins
create rooms and choose members from the portal. The first message is optional,
and new rooms are not assigned to a listing.

Authorization is enforced by `Api::V1::BaseController` and Pundit. Every
controller action either authorizes its record or declares a documented
public/webhook exception. Policies answer `view?`, `create?`, `update?`,
`destroy?`, and `manage?`; `manage?` means changing how a resource works for
others, such as configuring workflows or granting board access.

Required negative cases include:

- a customer cannot read another customer's listing, deliverable, or media;
- a customer cannot reference another listing's media in a review;
- a customer cannot review media that is not ready, current, and
  customer-visible;
- the legacy change-request endpoint cannot request changes from non-delivered
  work;
- private preview/download routes cannot be used across organizations;
- a specialist cannot read customer billing or an ungranted customer chat;
- board members cannot move tasks on boards they cannot access;
- product components cannot cross organizations or nest packages;
- workflows cannot target another organization's board, user, or group;
- private media streaming authorizes the parent record before bytes are read.

Capabilities are serialized for rendering hints. The server remains the
authorization boundary even if a browser hides or shows the wrong control.

## Migration rules

- Keep relational product variant rows and existing order snapshots.
- Add product deliverable fields, product components, and order deliverables.
- Add workflow definitions, conditions, actions, mappings, runs, and steps.
- Add task placements and deliverable links; migrate existing tasks to home
  placements before removing redundant direct board/status storage.
- Do not merge customer conversations into one per account. Accounts may hold
  many conversations with explicit members; existing conversations and their
  memberships stay exactly as they are, including people who were auto-joined
  under the old rule. `Conversation.account_thread_for` is removed with the
  auto-join once account admins can create chats.
- Preserve existing media storage keys and storage boundaries.
- Do not backfill old approved orders into new deliverables unless explicitly
  requested; new approvals use the materializer.
- Do not create `listing_services`, `revision_requests`, or JSON pricing arrays.
- Do not store a plan Markdown path or task-plan reference in runtime data.
- Any cleanup of legacy columns happens only after every API and UI path uses
  the replacement relationship and a migration spec covers existing rows.

## Verification plan

The backend has unit/service/job coverage and request-level API scenarios. The
critical test matrix includes:

### Unit and service tests

- product component organization, package, nesting, quantity, and ordering rules;
- deliverable scopes, statuses, customer-visible asset filtering, and lineage;
- workflow condition matching and status mapping validation;
- approval materialization for standalone services and package components;
- business-day target dates and idempotent materialization;
- workflow runner parent/child creation, grouping, placement, assignment,
  warnings, retries, and idempotency;
- task mover status, completion time, shared placement synchronization, and
  linked deliverable status;
- workflow trigger and job execution boundaries.

### Request and scenario tests

- catalog component CRUD and cross-organization denial;
- published customer media to portal review, with optional order/workflow
  lineage when it exists;
- package billing once while creating multiple production deliverables;
- shared tasks moving across multiple boards;
- workflow definition/run-history manager-only access and failed-run retry;
- portal listing/deliverable/media access-control negatives;
- API-relative preview/download serialization with no storage keys;
- chat account-thread creation, unread ordering, message context, and private
  attachment upload/preview failures;
- selected media reference validation and change-request transition;
- media-review snapshots, private draft comments, asset anchors, review
  outcomes, explicit approval, unlinked customer-visible media, change-request
  transitions, notifications, and review-thread authorization;
- board attachment access, content-type validation, and storage boundaries;
- migration preservation of existing task/conversation rows.

### Local commands

The test suite uses PostgreSQL on `localhost:5432`. In a sandboxed Codex
session, grant local-service/elevated access before the first invocation:

```bash
env -u DATABASE_URL TEST_DATABASE_URL=postgresql://localhost/project_red_crm_test \
  RAILS_ENV=test bundle exec rspec
```

Targeted examples are appropriate while diagnosing one failure. The full suite
is run once when the feature is complete and before a push. Always report the
exact example and failure counts. Run RuboCop with cache disabled when the
environment cannot write its default cache:

```bash
bundle exec rubocop --cache false
```

The UI must pass:

```bash
pnpm exec tsc --noEmit
pnpm run build
```

After code and specs pass, perform browser smoke checks for staff board/workflow
navigation, catalog package editing, staff listing media, portal listing media,
media review comments/outcomes, chat attachment display, and Escape/error
behavior.

## Completion criteria

The implementation is complete when:

- a service can be sold alone or included in a package;
- the package is billed once and approval creates durable deliverables;
- deliverables create linked, retry-safe workflow tasks;
- a task can appear on multiple authorized boards and move them together;
- task movement updates internal and customer-facing delivery state;
- staff can upload, reorder, version, preview, and download media in the CRM;
- customers can view/download only authorized ready media;
- customers can review delivered work, comment on selected assets, approve it, or
  request changes from the review workspace;
- review notifications appear in the account conversation without copying
  existing assets into chat;
- workflow runs and failed retries are visible to managers;
- staff and customer UIs use the supplied hierarchy and audience boundaries;
- chat and issue editors share attachment, URL, error, and keyboard behavior;
- the full backend suite, UI checks, and browser smoke checks have passed.

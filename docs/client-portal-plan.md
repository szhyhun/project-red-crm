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
relative `preview_path` and `download_path` values. It never exposes a storage
key, private bucket URL, or raw CDN construction to React.

Preview routes authorize the parent record before streaming. Download routes
may redirect to a short-lived signed URL only after the same authorization
check. UI media tags resolve serialized paths through `apiUrl`,
`mediaAssetUrl`, `mediaAssetDownloadUrl`, and `apiMediaNeedsCredentials`.

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
 ├── branded organization header and account menu
 ├── Dashboard
 ├── Listings
 ├── Orders
 ├── Messages
 └── Account
```

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
blank regions. A card includes service title, readable description, status,
target/delivered date, asset count, downloads, and Request Changes only when
the work is delivered.

Customer media presentation is type-specific:

- photography: thumbnails, full preview, multi-select, download selected/all;
- video: poster, duration, watch, download;
- floor plan: preview, download, and an interactive viewer when available;
- files: filename, type, size, and download.

There is no customer Add button. A new customer file is sent as a private
conversation attachment.

### Change requests

Request Changes opens a card-level drawer or mobile full-screen composer with
the listing, service, selected existing assets, rich-text message, attachment
control, and Submit request. The request is stored as a normal account-wide
conversation message with structured context:

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
On success the customer sees “Your request was sent” and the service moves to
in progress. The request appears in the same staff/customer conversation; no
separate `revision_requests` table is needed.

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
when the user is a member of at least one customer conversation. Customer
conversations are account-wide and carry listing/service context when a
message concerns a property.

The chat editor and issue comment editor share rich-text behavior:

- attachments with previews, progress, retry, and API-relative media paths;
- safe HTML sanitization and plain-text fallback;
- dismissible upload errors that clear on navigation or a successful action;
- Escape closes dialogs, drawers, menus, and popups;
- the first available conversation is selected on the Messages page;
- unread conversations sort before read conversations, by latest unread message;
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

Authorization is enforced by `Api::V1::BaseController` and Pundit. Every
controller action either authorizes its record or declares a documented
public/webhook exception. Policies answer `view?`, `create?`, `update?`,
`destroy?`, and `manage?`; `manage?` means changing how a resource works for
others, such as configuring workflows or granting board access.

Required negative cases include:

- a customer cannot read another customer's listing, deliverable, or media;
- a customer cannot reference another deliverable's media;
- a customer cannot request changes from non-delivered work;
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
- Merge existing listing-specific customer conversations into account-wide
  conversations while preserving message listing context and attachment keys.
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
- order approval to deliverables to workflow tasks to portal media;
- package billing once while creating multiple production deliverables;
- shared tasks moving across multiple boards;
- workflow definition/run-history manager-only access and failed-run retry;
- portal listing/deliverable/media access-control negatives;
- API-relative preview/download serialization with no storage keys;
- chat account-thread creation, unread ordering, message context, and private
  attachment upload/preview failures;
- selected media reference validation and change-request transition;
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
customer change requests, chat attachment display, and Escape/error behavior.

## Completion criteria

The implementation is complete when:

- a service can be sold alone or included in a package;
- the package is billed once and approval creates durable deliverables;
- deliverables create linked, retry-safe workflow tasks;
- a task can appear on multiple authorized boards and move them together;
- task movement updates internal and customer-facing delivery state;
- staff can upload, reorder, version, preview, and download media in the CRM;
- customers can view/download only authorized ready media;
- customers can request changes from delivered work with selected asset context;
- requests appear in the account-wide chat without copying existing assets;
- workflow runs and failed retries are visible to managers;
- staff and customer UIs use the supplied hierarchy and audience boundaries;
- chat and issue editors share attachment, URL, error, and keyboard behavior;
- the full backend suite, UI checks, and browser smoke checks have passed.

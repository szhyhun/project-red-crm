# Client portal build plan

Source: three design briefs — client dashboard, team/branding/social profiles, and
media page + revision workflow — read against the schema at version
`2026_08_19_104000`.

This file is the tracked version of the plan. Update the task checkboxes and the
rulings as work lands; the numbered task IDs (T1–T13) are documentation labels,
not database fields or runtime task metadata. The three source PDFs are product/design briefs: their prose
defines behavior and data requirements, while their screenshots are visual references
for hierarchy and interaction rather than pixel-perfect implementation instructions.

## Status summary

| | Count |
| --- | --- |
| Brief requirements | 47 |
| Fully built | 4 |
| Partial | 13 |
| Not started | 30 |
| New tables | 13 + deliverable services, pending research |

The backend is strong on commerce and operations — orders, invoices, payments,
pricing plans, appointments, Aryeo import, media storage with CDN delivery. It is
close to empty on the three things the briefs are actually about: a client-facing
view of production, revisions, and client-owned brand assets.

## Blockers and rulings

### 01 · Tasks cannot exist without a listing

`workflow_tasks.listing_id` is `null: false` and every write path goes through
`listing.workflow_tasks.build`. An internal development board is structurally
impossible until this is nullable.

**Ruling — make it optional.** A board carries `requires_listing`; production
boards keep the constraint at the application layer, internal boards drop it. T2.

### 02 · One implicit board per organization

There is no `boards` table. A board *is* the org's set of `workflow_columns`, and
a task joins its column by string: `workflow_tasks.status` matches
`workflow_columns.key`, enforced by `WorkflowTask#status_matches_organization_column`
and a unique index on `(organization_id, key)`.

**Ruling — not a blocker, just work.** Uniqueness moves to `(board_id, key)` and
the validation becomes board-scoped. T2.

### 03 · Pundit is installed but never enforced, and the UI re-implements it

Pundit is included in `ApplicationController`, but there is no `verify_authorized`,
so authorization is opt-in per action. Three idioms coexist: `authorize record`,
`authorize Model, :action?`, and hand-rolled
`return render forbidden unless current_user.internal?`. `dashboard#show` and
`client_portal#show` use the third and never touch a policy.

The frontend then derives the same rules a second time from the role string —
`canManageTeam = role === "organization_admin" || …` in `page.tsx:1353`, with
further copies in `shell.tsx` and `listing-workspace.tsx:1417`.

**Ruling — build a capability layer.** Keep Pundit, make authorization the
controller default, give every policy the same question set, and serialize the
answers so the UI consumes them instead of re-deriving them. T1, and it goes first.

### 04 · Nothing tracks a service's production state

`order_items` carry no status, no ETA, no link to the deliverables that satisfy
them. `media_assets.category` has five values (`images·videos·floor_plans·tours·files`)
and cannot tell Video from Vertical Reel from Drone.

**Ruling — deferred to research.** T5 is a timeboxed spike producing the model and
its own sized follow-ups. Phase G is blocked behind it; Phases D–F are sequenced so
none of them wait.

### 05 · Internal status vocabulary leaks to clients

The portal renders `listing.status` and `workflow_task.status` directly into a
`StatusPill`. Because workflow columns are org-configurable, whatever a manager
names a column becomes client-facing copy. All three briefs forbid this.

**Ruling — agreed.** The client-facing lifecycle becomes a derived, closed
vocabulary that internal states map *into*, with a serializer test asserting no
internal string can escape. Presenter boundary lands with T6.

## Authorization model

### Pundit, not CanCanCan

Pundit is already installed with 21 policy files and correct `policy_scope` usage.
CanCanCan would mean rewriting all of it to get a vocabulary Pundit expresses
as-is. The gap is not the library — it is that nothing enforces it and nothing
publishes it.

### 1 · Authorization is the default

```ruby
class Api::V1::BaseController < ApplicationController
  after_action :verify_authorized,    unless: :index_action?
  after_action :verify_policy_scoped, if:     :index_action?
end
```

Filtered with `if:` rather than `only: :index`: Rails raises
`AbstractController::ActionNotFound` when an `only:` names an action a controller
does not define, and most controllers here have no index.

**Why `after_action` and not `before_action`.** `verify_authorized` does not
authorize; it checks whether `authorize` *was called*, by reading a flag that
`authorize` sets inside the action body (`pundit/authorization.rb:92`). As a
`before_action` the flag is never set yet, so it would raise on every request.
There is no before-action form of this check.

What it does and does not protect:

- Rails runs `after_action` after the action body but **before the response reaches
  the client**, so a raise discards the rendered body.
- **Side effects still happen.** A `create` that forgot to authorize has already
  committed its row when the callback fires.
- **Streamed responses escape it.** `media_assets#download` and `#preview` use
  `send_file`. Both authorize correctly today, and get explicit specs rather than
  relying on the tripwire.
- It is a programmer-error tripwire, not the security control. The control is the
  `authorize` call.

`AuthorizationNotPerformedError` descends from `Pundit::Error`, not from
`NotAuthorizedError`, so the existing `rescue_from Pundit::NotAuthorizedError` does
not swallow it — a forgotten `authorize` surfaces as a 500, not a quiet 403.

Pair it with a CI request spec walking every route and asserting each action
authorizes or declares a skip. That is the pre-deploy guarantee the runtime
callback cannot give.

### 2 · One question set on every policy

```ruby
class ApplicationPolicy
  CAPABILITIES = %i[view create update destroy manage].freeze

  def view?    = false
  def create?  = false
  def update?  = false
  def destroy? = false
  def manage?  = false   # configure the resource type: columns, settings, access

  def show?  = view?     # aliases so no existing policy breaks
  def index? = view?

  def capabilities
    self.class::CAPABILITIES.select { |c| public_send(:"#{c}?") }
  end
end
```

`manage?` is the new question. It separates "can edit this record" from "can change
how this resource works for everyone" — deleting a workflow column, granting board
access, editing the catalog.

### 3 · The answers ship to the client

```jsonc
// Per record
GET /api/v1/boards/7
{ "board": { "id": 7, "name": "Engineering",
             "capabilities": ["view", "update", "manage"] } }

// Per session
GET /api/v1/auth/me
{ "user": { },
  "capabilities": { "boards": ["view", "create"], "staff": [] } }
```

### 4 · Denials say what was denied

```jsonc
{ "error": "forbidden", "resource": "Board", "action": "update",
  "message": "You don't have manage access to this board." }
```

### 5 · The UI consumes, never re-derives

Every `role === "…"` comparison in the frontend is deleted and replaced with
`useCapabilities()` / `<Can>` reading the payloads above. Navigation is built from
the session capability map rather than an `adminAccess` boolean.

**Capabilities are a UI hint, never the boundary.** The server authorizes every
request regardless of what the client was told.

## Board design

### Schema

```
boards
  organization_id, name, slug (unique per org), description,
  kind             production | internal | custom
  visibility       organization | restricted
  requires_listing boolean
  client_visible   boolean      -- gates customer_visible tasks
  archived, position, created_by_id, settings jsonb

user_groups                     -- "Developers", "Editors", "Dispatch"
  organization_id, name, slug (unique per org), description

user_group_memberships
  user_group_id, user_id        -- unique together

board_memberships               -- polymorphic grantee: a user OR a group
  board_id, member_type ("User" | "UserGroup"), member_id
  access           viewer | contributor | manager

workflow_columns   + board_id;  unique (organization_id, key) → (board_id, key)
workflow_tasks     + board_id, reporter_id, labels[], started_at
                   ~ listing_id NULL allowed
```

Backfill in one migration: create a `Production` board per organization, repoint
every existing column and task, then apply `NOT NULL`.

### Access rules

1. `visibility: organization` — every internal user in the org can view. Writes
   fall back to role rules.
2. `visibility: restricted` — only users with a `board_membership`, directly or
   through a `user_group`. This is how "developers and admins only" works.
3. `organization_admin` always sees and manages every board in their org. There is
   no hidden-from-the-admin board.

Client users never reach boards. `customer_visible` tasks stay client-readable only
when the board is `client_visible`.

```ruby
BoardPolicy#view?   → visibility == 'organization' || member? || admin?
BoardPolicy#update? → access >= :contributor
BoardPolicy#manage? → access == :manager || admin?

WorkflowTaskPolicy#update?   → policy(record.board).update?
WorkflowColumnPolicy#manage? → policy(record.board).manage?
```

### API

```
GET    /api/v1/boards
POST   /api/v1/boards
PATCH  /api/v1/boards/:id
DELETE /api/v1/boards/:id                 archive, never hard-delete with tasks
GET    /api/v1/boards/:id/members
POST   /api/v1/boards/:id/members         { member_type, member_id, access }
DELETE /api/v1/boards/:id/members/:id

GET    /api/v1/boards/:board_id/workflow_columns
GET    /api/v1/boards/:board_id/workflow_tasks
POST   /api/v1/boards/:board_id/workflow_tasks

GET    /api/v1/user_groups                + CRUD, organization_admin only
POST   /api/v1/user_groups/:id/members

Back-compatible, the deployed UI calls these unscoped:
GET /api/v1/workflow_columns  → the org's default production board
GET /api/v1/workflow_tasks    → all visible boards, each row carrying board_id
```

## Portal domain design

### Deliverable services — research pending (T5)

Not committed to. Open questions for the spike:

- Own table, or a status on `order_item`? What happens when the order item is
  cancelled?
- Service types as a hardcoded enum, or catalog-configurable per organization?
  Aryeo-imported products must map into whichever it is.
- How does an off-order service enter — a comp reshoot, a goodwill re-edit?
- Migration path for `media_assets.category` without breaking `DeliveryArchive` or
  the public property site.
- ETA: staff-entered, catalog-defaulted, or computed — and what renders when unknown.

Starting sketch only:

```
listing_services
  organization_id, listing_id, order_item_id (nullable)
  service_type      photography | video | vertical_reel | drone | floor_plan |
                    matterport | property_website | virtual_staging | twilight | files
  name              client-facing label
  production_state  pending_shoot | shot | editing | qc | ready | delivered |
                    revising | cancelled
  eta_at, delivered_at, asset_count, position, metadata

media_assets  + listing_service_id, version, superseded_by_id
```

Client-facing status is **derived, never stored twice**. A `ClientStatus` presenter
maps `production_state` plus revision state into the closed vocabulary the briefs
specify; the listing badge rolls up from the services beneath it.

### Revisions

One open thread per listing + service, with asset-level references inside it.

```
revision_requests
  organization_id, listing_id, listing_service_id, opened_by_id
  status  submitted | reviewing | in_progress | updated_ready | client_review | completed
  kind    revision | pre_delivery_note
  eta_at, cycle, opened_at, closed_at
  partial unique index (listing_service_id) WHERE status != 'completed'

revision_messages
  revision_request_id, author_id, body, visibility, attachments jsonb

revision_references
  revision_message_id, media_asset_id, timecode_ms, locator jsonb, note
```

The partial unique index is what makes the *Open Request* button copy truthful.

### Client account financials

```
credit_transactions          -- append-only; balance is SUM, never a column
  organization_id, client_account_id, amount_cents (signed),
  kind (bonus | refund | adjustment | applied), reason, invoice_id, created_by_id

account_benefits             -- the client-facing face of a pricing plan
  client_account_id | customer_team_id  (exactly one, like pricing_plans)
  label, rate_basis_points, order_code, permanent, expires_on, active
```

`account_benefits` is a display record beside `pricing_plans`, not a rewrite of
them. Pricing plans stay authoritative for what an order costs.

### Brand profile

```
brand_profiles               -- one per client_account
  display_name, title, brokerage_name, office, phone, email,
  website, brokerage_website, bio, socials jsonb

brand_assets                 -- versioned; old materials keep their version
  brand_profile_id, media_asset_id
  slot     primary_logo | alternate_logo | brokerage_logo | headshot | team_logo | other
  version, current
  partial unique index (brand_profile_id, slot) WHERE current
```

Replace writes a new row and flips `current`; it never destroys the old one.

### Portal frontend architecture

The staff app is one client-rendered SPA — `page.tsx` is 1,701 lines and
`globals.css` 5,154, shared by staff and client alike. The portal is a different
product for a different audience with a hard accessibility floor.

- Own route group `app/(portal)/` with its own layout and stylesheet.
- Accessibility floor as tokens: 17px body minimum, 44px targets, AA contrast in
  both themes, no hover-only or icon-only primary actions.
- One `ListingCard` used at three densities by dashboard, listings index, and
  Recently Delivered.
- One `ServiceStatus` owning the closed status vocabulary and its colour logic. A
  status string rendered anywhere else is a bug.

## Tasks

Vertical slices — schema, API and interface for a single capability. Sizes are
rough working days for one engineer. The synced board copy is intentionally
human-first: each issue starts with the user problem and expected behaviour,
then records the technical proposal, source brief (when applicable), and done
conditions. The plan is documentation only; board issues do not store a
database reference back to this file.

### Phase A — Authorization and boards

- [~] **T1 · Protect every CRM action with server-side authorization** — 4d — *no deps* — **backend done, frontend outstanding**
  - `verify_authorized` / `verify_policy_scoped` as `after_action` in `Api::V1::BaseController`,
    explicit skips on webhook, sign-up and public site endpoints.
  - CI request spec walking every route, asserting each action authorizes or skips.
  - `ApplicationPolicy` question set + `#capabilities`; `show?`/`index?` alias `view?`.
  - Convert `dashboard#show` and `client_portal#show` off hand-rolled role guards.
  - Per-record `capabilities` in serializers; session capability map on `/auth/me`;
    403 bodies carrying resource, action and message.
  - Frontend `useCapabilities()` / `<Can>`; remove every `role === …` check from
    `page.tsx`, `shell.tsx`, `listing-workspace.tsx`; handle 403 by showing the API
    message and refreshing `/auth/me`.
- [x] **T2 · Create separate boards with clear team access** — 7d — *T1*
  - Schema, backfill, `BoardPolicy` + scope, board-scoped endpoints and
    back-compat routes: done.
  - Switcher, create/edit modal, member manager and groups panel: done.
  - `WorkflowTasks::Mover` repositions within a board; `customer_visible` gated on
    the board's `client_visible`.
- [x] **T3 · Make issue details useful for planning and discussion** — 3d — *T2*
  - Task descriptions and comments remain editable, board-authorized, and capable of
    carrying sanitized rich media references; labels are shared board configuration,
    comments allow one reply level, and board attachments are tracked separately in B1.

### Phase B — Put the plan on the board

- [x] **T4 · Keep the Engineering board plan understandable** — 1d — *T3*
  - Seeded the agreed plan items as ordinary board issues with human-readable
    titles, descriptions, and board-owned labels. The Markdown plan and PDF
    briefs remain planning references, not runtime task metadata.

### Board platform follow-up

- [x] **B1 · Add rich issue content and attachments** — 5d — *T3* — **delivered in the current board release**
  - Allow issue descriptions and comments to contain safe rich text plus attached images,
    video, and supporting files. Store attachment metadata and board/organization ownership
    in the API, upload bytes to a dedicated board-media S3 bucket behind the existing CDN,
    and return authorized preview/download URLs rather than raw bucket paths.
  - Enforce board access for every attachment read, upload, replacement, and deletion;
    validate content type, size, and filename, and prevent cross-organization references.
    Add request specs for unauthorized access and a UI composer that supports previews,
    progress, retry, remove, and video poster/duration metadata where available.

### Phase C — Research

- [ ] **T5 · Define how each property service moves from order to delivery** — 3d timeboxed — *no deps* — **blocks Phase G**

### Phase D — Portal data

- [ ] **T6 · Give clients a property-first listings API** — 5d — *T1*
  - `property_status`, `property_type`, `price_cents`, `bedrooms`, `bathrooms`,
    `square_feet`, `lot_acres`, `parking`, `year_built`, `mls_number`, and
    `mls_live_date`, with client values such as Coming Soon, For Sale, For Lease,
    Pending Sale, Pending Lease, For Rent, Sold, and List Off Market.
  - Closed client lifecycle enum + presenter boundary, derived from appointments
    and `delivered_at` for now.
  - `GET /portal/dashboard`, listing index/detail, `POST /portal/listings`, and retirement
    of `client_portal#show`; new listings begin as draft/booking requests and remain
    property-first rather than order-first.
- [ ] **T7 · Show clients what they owe and what benefits they have** — 3d — *T1*
  - Dashboard-visible amount due across unpaid invoices/outstanding orders, credit or bonus
    balance, active/permanent discounts, brokerage or referral code, and expiry when relevant.

### Phase E — Portal interface

- [ ] **T8 · Build a clear, property-first client home page** — 8d — *T6, T7*
  - Property-first HOME/LISTINGS/CREATE/PROMOTE/ACCOUNT navigation, welcome/CTA, quick
    actions, active listing cards with hero image, search/filter, upcoming shoots, and
    recently delivered work. Keep property marketing status separate from production status.
  - Show the account summary without a deep settings click: amount due, credit/bonus,
    discount/benefit, and brokerage order code. Use readable client statuses, generous
    spacing, large targets, high contrast, mobile card layouts, and no hidden primary actions.
  - Includes the AI assistant entry point (button + context payload only); no AI answer
    backend is in scope.
- [ ] **T9 · Give each property one workspace for all its work** — 4d — *T8*
  - Make each property the durable workspace entry point for Overview, Media, Revisions,
    Property & MLS Details, Property Website, Marketing, Orders/Services, Payments, and
    Activity navigation. Do not make clients choose an internal order number.

### Phase F — Brand and team

- [ ] **T10 · Let clients manage their brand and social profiles once** — 6d — *T8*
  - Centralize logos, headshots, brokerage/team assets, social links, and public contact
    data so future property websites, marketing materials, promotion, social content, and
    feature sheets reuse the current profile. Show previews, completeness/attention state,
    replace actions, and preserve older assets for historical materials.
- [ ] **T11 · Let clients manage who can access their account** — 3d — *T1, T8*
  - Support invite/list/revoke and simple scopes for full account, listing-only, media,
    billing, and marketing access; prevent revoked or cross-account members from reading
    listings, media, or actions.

### Phase G — Media and revisions

- [ ] **T12 · Show every ordered service with status and downloads** — 7d — *T5, T9*
  - Keep every ordered service visible in a property workspace: Photography, Video, Vertical
    Reel, Drone, Floor Plan, Matterport/3D Tour, Property Website assets, Files, and future
    service types. Show service-specific status, ETA/delivery time, asset count, View/Watch,
    Download, and Request Changes without exposing queued/rendering/pipeline terminology.
- [ ] **T13 · Let clients request and track changes by service** — 8d — *T12*
  - One open contextual thread per Listing + Service, with selected-photo references,
    video timestamps, floor/room/page locators, attachments, messages, ETA, status, and
    version history. Reuse the thread for follow-up messages, prevent duplicate open
    requests, and expose the thread status on its service card. Support a client side panel
    or mobile full-screen composer, staff ownership/queue, and client-safe download/review
    transitions.

### Source brief coverage check

Every requirement from the three source briefs is assigned to at least one board issue;
the PDFs are the product source, while the task descriptions translate them into
implementation boundaries.

| Brief area | Board issues |
| --- | --- |
| Client dashboard shell, navigation, quick actions, listing cards, search, mobile/accessibility, and AI entry point | T8 |
| Property facts, client-safe property/production status, listing creation, and account financial summary | T6, T7, T8 |
| Property-first listings index and durable listing workspace navigation | T9 |
| Team invitations, membership visibility, and permission scopes | T11 |
| Central branding, social profiles, reusable assets, previews, replacement, and version history | T10 |
| Service-level media tracker, delivery states, ETAs, downloads, and request changes | T5, T12 |
| Contextual revision threads, selected assets, timestamps/locators, attachments, versions, staff queue, and lifecycle | B1, T13 |

No brief requirement is intentionally left without an owner; if a requirement changes,
update the owning issue and this matrix together.

**Roughly 62 engineering days for the remaining portal slices.** Critical path T1 → T2 → T6 → T8 → T12 → T13. T1 has the widest
blast radius; T5 carries the most uncertainty, so start the spike early even though
nothing in Phases D–F waits on it.

## Open decisions

**Does the portal stay in the staff Next.js app?** Recommended: same repo, own
route group with its own layout and stylesheet (T8). Same deploy, same auth
session, no shared CSS blast radius.

**Do clients create listings directly, or request them?** Recommended: a
client-created listing enters as `draft` with a booking request, staff confirm into
`booked`. The client sees "Coming Soon".

**Are ETAs entered or computed?** Recommended, as an input to T5: staff-entered per
service, with a per-service-type default turnaround seeded from the catalog. Render
nothing when unknown.

**Is the internal board visible to organization admins?** Recommended: yes. An
admin who cannot audit a board in their own tenant is a support problem, not a
privacy feature. If a genuinely private board is needed, add `visibility: private`
explicitly rather than weakening the admin rule.

## Out of scope

- Context-aware AI answering. T8 ships the entry point and context payload only.
- The Promote section. Nav slot and route stub only.
- Property website editor. Rendering the branded site is the marketing site's job.
- Matterport / 3D tour embedding. Carried into T5 as a service type; the viewer
  integration is not scoped here.

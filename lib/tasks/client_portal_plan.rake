namespace :project_red do
  PLAN_TASKS = [
    {
      external_ref: "T1",
      title: "Capability-based authorization, enforced by default",
      description: <<~DESCRIPTION.strip,
        Scope: Make Pundit authorization the default for every API request. Add `view?`, `create?`, `update?`, `destroy?`, and `manage?` to the shared policy contract, with `show?` and `index?` aliases and serialized capabilities.

        Implementation: enforce `verify_authorized` and `verify_policy_scoped` as API after-actions; convert dashboard and client-portal guards to policies; expose per-record capabilities, the `/auth/me` session capability map, and structured 403 responses containing the resource, action, and message. Add route coverage that requires every action to authorize or declare an explicit skip for public, webhook, sign-up, or authentication endpoints.

        Done when: the frontend consumes `useCapabilities()` or `<Can>` instead of role comparisons, handles the API's 403 message, and the server remains the authorization boundary.
      DESCRIPTION
      labels: %w[backend frontend security]
    },
    {
      external_ref: "T2",
      title: "Multiple boards with per-person and per-group access",
      description: <<~DESCRIPTION.strip,
        Schema: Add first-class `boards`, `user_groups`, group memberships, and polymorphic board memberships. Move workflow-column uniqueness to `(board_id, key)`, add `board_id` to columns and tasks, make `workflow_tasks.listing_id` nullable, and add `requires_listing` and `client_visible` board flags. Backfill a Production board, repoint existing records, and enforce the new foreign keys.

        API and access: provide board CRUD/archive, member and group management, board-scoped column/task endpoints, and compatible visible-task reads. Organization-visible boards are readable by internal staff; restricted boards require direct or group membership; organization admins retain management access. Client users never reach internal boards, and customer-visible tasks are gated by the board.

        Done when: policies and scopes make board isolation unconditional, task movement stays inside one board, and a user who cannot view a board receives no task data from it.
      DESCRIPTION
      labels: %w[backend frontend schema security],
      completed: true
    },
    {
      external_ref: "T3",
      title: "Task detail: comments, checklists, labels",
      description: <<~DESCRIPTION.strip,
        Schema and API: add `task_comments` and `task_checklist_items` with author/completion metadata, ordering, and timestamps. Store normalized labels on the task and allow them to be edited with the task update endpoint. Add create/update/delete endpoints for comments and checklist items, all authorized through the parent task's board.

        Interface: expose a task detail view that can read and edit the description, labels, comments, and checklist; return only comment/checklist counts in board-card payloads and include full detail collections on the detail endpoint.

        Done when: every detail mutation is denied outside the board's access rules, checklist completion is attributable, labels are filterable on the board, and card payloads stay lightweight.
      DESCRIPTION
      labels: %w[backend frontend],
      completed: true
    },
    {
      external_ref: "T4",
      title: "Seed the Engineering board from these briefs",
      description: <<~DESCRIPTION.strip,
        Data task: create an idempotent `project_red:sync_plan_tasks` rake task that reads the numbered T1–T13 briefs and upserts one record per `external_ref` on the Engineering board. Set the full title, actionable description, position, area/brief labels, and `listing_id: nil`; rerunning it must update metadata without duplicating issues or changing manually selected positions.

        Workflow: map T2, T3, and T4 to the board's completed column because those slices are already delivered. Leave T1 and T5–T13 in their current or default open status, and fail clearly if the board has no workflow columns or completed column.

        Done when: the sync is safe for every organization with an Engineering board, can be rerun after plan edits, and the board contains all thirteen standalone engineering issues with the plan's descriptions and labels.
      DESCRIPTION
      labels: %w[backend schema data brief-1 brief-2 brief-3],
      completed: true
    },
    {
      external_ref: "T5",
      title: "Deliverable services design spike",
      description: <<~DESCRIPTION.strip,
        Research spike: decide whether a deliverable is its own record or an `order_item` state, how cancelled and off-order services (for example a reshoot or goodwill re-edit) enter the workflow, and whether service types are fixed or catalog-configurable. Define the production state and ETA vocabulary that the portal can safely expose.

        Schema/API output: evaluate a `listing_services` model linking an organization and listing to an optional order item, with service type, production state, ETA, and delivery metadata. Document how Aryeo products map into it and how `media_assets.category` can migrate without breaking DeliveryArchive or the public property site.

        Done when: the spike produces a written decision, migration/API implications, and sized follow-up tasks for Phase G; do not start the media implementation until those decisions are recorded.
      DESCRIPTION
      labels: %w[backend schema research]
    },
    {
      external_ref: "T6",
      title: "Portal listing API: property facts, dashboard, listing creation",
      description: <<~DESCRIPTION.strip,
        Schema/API: add the client-facing property facts `property_status`, `property_type`, `price_cents`, `lot_acres`, `parking`, `year_built`, and `mls_live_date`. Build `GET /portal/dashboard`, listing index/detail data, and `POST /portal/listings` so a client-created listing starts as a draft or booking request according to the approved lifecycle.

        Presentation boundary: derive a closed client lifecycle from appointments, delivery, and internal production state. Serialize only that vocabulary; internal workflow-column names and raw `listing.status` values must never leak to the client. Retire `client_portal#show` after the new endpoint is equivalent and policy-authorized.

        Done when: API request and serializer specs cover authorization, creation, dashboard data, and the no-internal-status guarantee, with capabilities included in the response.
      DESCRIPTION
      labels: %w[backend api portal schema]
    },
    {
      external_ref: "T7",
      title: "Account financials: credit, benefits, order codes",
      description: <<~DESCRIPTION.strip,
        Schema: add append-only `credit_transactions` with signed `amount_cents`, kind, reason, invoice linkage, and actor; calculate balance as the sum rather than storing a mutable balance column. Add `account_benefits` as the client-facing display beside pricing plans, with a single client account or customer team owner, rate basis points, order code, permanence, expiry, and active state.

        API and commerce: expose the account's current credits, benefits, and valid order codes through authorized portal endpoints. Apply credits and benefits server-side to commerce flows while leaving `pricing_plans` authoritative for order pricing; reject expired, inactive, cross-account, or unauthorized applications.

        Done when: financial mutations are auditable and append-only, money remains integer cents, access is covered by negative policy specs, and the portal can show the same values the order calculation uses.
      DESCRIPTION
      labels: %w[backend api billing]
    },
    {
      external_ref: "T8",
      title: "Portal shell and dashboard home",
      description: <<~DESCRIPTION.strip,
        Frontend: create an isolated `app/(portal)/` route group with its own layout and stylesheet rather than extending the staff SPA's role logic. Meet the accessibility floor: 17px minimum body text, 44px targets, AA contrast in both themes, and no hover-only or icon-only primary actions.

        Dashboard: build navigation, summary metrics, and recent listings using one reusable `ListingCard` at the required densities. Add one `ServiceStatus` component that owns the closed client lifecycle and color mapping; raw internal status strings rendered outside it are a bug.

        Integration: consume the T6/T7 portal APIs and capabilities. Ship the AI assistant button plus a context payload for the current account/listing only; no AI answering backend is part of this task. Done when keyboard, responsive, loading, empty, and forbidden states are covered.
      DESCRIPTION
      labels: %w[frontend portal api]
    },
    {
      external_ref: "T9",
      title: "Listings index and listing workspace shell",
      description: <<~DESCRIPTION.strip,
        Frontend/API slice: build the portal listings index and a listing workspace shell that gives a client one place to understand a property. Include property facts, customer/account context, production activity, appointments, media, and delivery links with loading, empty, and denied states.

        Reuse the dashboard's `ListingCard` and `ServiceStatus` components so cards and workspace headers use the same client vocabulary. Fetch only listings the current account and team scope may view; do not expose internal board columns or unrelated organization records.

        Done when: the index links to a stable listing workspace, the workspace can be extended by media and revision slices, API/policy specs cover cross-account access, and the UI works at all supported card densities.
      DESCRIPTION
      labels: %w[frontend backend portal]
    },
    {
      external_ref: "T10",
      title: "Account area: branding, social profiles, billing",
      description: <<~DESCRIPTION.strip,
        Schema: add one `brand_profile` per client account for display name, title, brokerage, contact details, websites, bio, and social links. Add versioned `brand_assets` linked to media assets with slots such as primary logo, alternate logo, brokerage logo, headshot, and team logo; enforce one current asset per profile and slot with a partial unique index.

        API/UI: build authorized account pages for branding, social-profile, and billing settings. Replacing an asset creates a new version and flips `current`; it must not destroy the previous material. Keep organization/admin and client-account boundaries explicit, and keep pricing-plan authority separate from display settings.

        Done when: old brand versions remain recoverable, current-slot conflicts are impossible at the database level, and policy specs prevent another account from reading or changing branding or billing data.
      DESCRIPTION
      labels: %w[frontend backend portal]
    },
    {
      external_ref: "T11",
      title: "Client team management and permission scopes",
      description: <<~DESCRIPTION.strip,
        Access model: add client-team invitations and membership records with permission scopes for listings, media, and account actions. A member may be limited to selected listings or granted account-wide access according to the approved scope vocabulary; invitation acceptance must not cross organization or client-account boundaries.

        API/UI: provide team listing, invite, revoke, and scope-management endpoints plus an account settings panel. Serialize capabilities for the current user, authorize every mutation on the server, and keep staff board permissions separate from client-team permissions.

        Done when: a client manager can administer their own team, a scoped member sees only permitted listings/media/actions, expired or revoked invitations cannot be used, and negative policy/request specs prove cross-account access is denied.
      DESCRIPTION
      labels: %w[backend frontend security]
    },
    {
      external_ref: "T12",
      title: "Media page: per-service delivery and downloads",
      description: <<~DESCRIPTION.strip,
        Data/API: implement the `listing_services` and media-delivery boundary decided in T5. A service must carry a client-safe type, production state, ETA when known, and links to its delivered `media_assets`; support photography, video, vertical reel, drone, floor plan, and tour without overloading the old generic category.

        Frontend: build a media page grouped by service, showing the closed client status, delivered assets, download actions, and an honest empty/in-progress state. Enforce client visibility at the policy and serializer layers, and route downloads through the existing storage/CDN boundary rather than exposing internal paths.

        Done when: a client cannot see another account's assets or staff-only media, each service's delivery state is traceable to its assets, and storage/CDN plus migration behavior is covered by integration specs.
      DESCRIPTION
      labels: %w[backend frontend media]
    },
    {
      external_ref: "T13",
      title: "Revision threads, versioning and the staff queue",
      description: <<~DESCRIPTION.strip,
        Schema: add `revision_requests` with listing/service, opener, status, kind, ETA, cycle, and opened/closed timestamps; add `revision_messages` with visibility and attachments; add `revision_references` for media assets, timecodes, locators, and notes. Enforce one open request per listing service with a partial unique index while allowing completed history.

        Workflow/API: let clients submit a revision or pre-delivery note against a delivered service, attach precise asset references, and review versioned updates. Give staff a queue with ownership, status transitions, ETA, and audit history; feed accepted feedback into trackable engineering/production work rather than an unstructured comment.

        Done when: open-request state is truthful, client/staff visibility is policy-scoped, asset versions remain inspectable, and request/message/reference mutations have negative authorization coverage.
      DESCRIPTION
      labels: %w[backend frontend media workflow]
    }
  ].freeze

  desc "Synchronize the client portal plan issues on each organization's Engineering board"
  task sync_plan_tasks: :environment do
    organizations = if ENV["ORGANIZATION_SLUG"].present?
      [ Organization.find_by!(slug: ENV["ORGANIZATION_SLUG"]) ]
    else
      Organization.all
    end

    organizations.each do |organization|
      board = organization.boards.find_by(slug: "engineering")
      next if board.blank?

      default_status = board.workflow_columns.ordered.first&.key
      raise "#{board.name} has no workflow columns" if default_status.blank?
      completed_status = board.workflow_columns.find_by(category: "completed")&.key
      raise "#{board.name} has no completed column" if completed_status.blank?

      PLAN_TASKS.each_with_index do |definition, position|
        task = board.workflow_tasks.find_or_initialize_by(external_ref: definition.fetch(:external_ref))
        completed = definition.fetch(:completed, false)
        task.assign_attributes(
          organization:,
          title: definition.fetch(:title),
          description: definition.fetch(:description),
          labels: definition.fetch(:labels),
          listing_id: nil,
          position: task.persisted? ? task.position : position,
          status: completed ? completed_status : (task.status.presence || default_status),
          completed_at: completed ? (task.completed_at || Time.current) : task.completed_at
        )
        task.save!
      end

      puts "Synchronized #{PLAN_TASKS.length} plan tasks on #{organization.slug}/#{board.slug}"
    end
  end
end

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
      labels: %w[backend frontend security],
      status: "in_progress"
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
        Schema and API: add `task_comments` and `task_checklist_items` with author/completion metadata, ordering, and timestamps. Store labels as board-owned records and assign only labels configured on the task's board through the task update endpoint. Add create/update/delete endpoints for comments and checklist items, all authorized through the parent task's board.

        Interface: expose a task detail view that can read and edit a multiline description, labels, comments, and checklist. Comments support one level of replies; descriptions and comments use sanitized rich text, while B1 owns the board attachment upload/storage flow. Return only comment/checklist counts in board-card payloads and include full detail collections on the detail endpoint.

        Done when: every detail mutation is denied outside the board's access rules, checklist completion is attributable, labels are filterable on the board, descriptions/comments are usable for implementation notes, and card payloads stay lightweight.
      DESCRIPTION
      labels: %w[backend frontend schema],
      completed: true
    },
    {
      external_ref: "T4",
      title: "Seed the selected engineering board from these briefs",
      description: <<~DESCRIPTION.strip,
        Data task: create an idempotent `project_red:sync_plan_tasks` rake task that reads the numbered T1–T13 briefs and the B1 board-content follow-up, then upserts one record per `external_ref` on the selected engineering board. Set the full title, actionable description, position, board-owned area/brief labels, and `listing_id: nil`; rerunning it must update metadata without duplicating issues or changing manually selected positions.

        Workflow: map T2, T3, T4, and B1 to the board's completed column because those slices are already delivered. Keep T1 in progress while its frontend capability migration remains, and leave T5–T13 in their current or default open status. Fail clearly if the board has no workflow columns or completed column.

        Done when: the sync is safe for every organization with an Engineering board, can be rerun after plan edits, and the board contains all portal issues plus the board-content follow-up with the plan's descriptions and labels.
      DESCRIPTION
      labels: %w[backend schema data brief-1 brief-2 brief-3],
      completed: true
    },
    {
      external_ref: "B1",
      title: "Rich issue content and board attachments",
      description: <<~DESCRIPTION.strip,
        Product need: make board issues useful as implementation briefs, not one-line tickets. Allow descriptions and comments to contain safe rich text plus attached images, videos, and supporting files so screenshots, reference photos, screen recordings, replacement logos, and documents can stay with the discussion.

        Storage/API: add attachment metadata owned by the organization, board, task, and comment; upload bytes to a dedicated board-media S3 bucket behind the existing CDN/storage boundary; return authorized preview and download URLs instead of raw bucket paths. Support image previews and video metadata such as content type, duration, and poster/thumbnail when available. Validate size, MIME type, filename, and upload completion, and make replacement/removal auditable.

        Authorization/UI: every read, upload, replace, and delete must pass the parent board/task/comment policy, with no cross-organization references. Add a composer with paste/select, upload progress, retry, preview, remove, and accessible alt text/caption controls. Done when unauthorized users cannot infer or fetch an attachment, and request specs cover board isolation and failed uploads.
      DESCRIPTION
      labels: %w[backend frontend schema security media],
      completed: true
    },
    {
      external_ref: "T5",
      title: "Deliverable services design spike",
      description: <<~DESCRIPTION.strip,
        Research spike: decide whether a deliverable is its own record or an `order_item` state, how cancelled and off-order services (for example a reshoot or goodwill re-edit) enter the workflow, and whether service types are fixed or catalog-configurable. Define the production state and ETA vocabulary that the portal can safely expose without showing queued, rendering, worker, or pipeline terminology.

        Schema/API output: evaluate a `listing_services` model linking an organization and listing to an optional order item, with client-facing name, service type, production state, ETA, delivered timestamp, asset count, position, and metadata. Cover Photography, Video, Vertical Reel, Drone, Floor Plan, Matterport/3D Tour, Property Website assets, Files, and future services. Document how Aryeo products map into it and how `media_assets.category` can migrate without breaking DeliveryArchive or the public property site.

        Done when: the spike produces a written decision, migration/API implications, client-safe status mapping, ETA rules, and sized follow-up tasks for Phase G; do not start the media implementation until those decisions are recorded.
      DESCRIPTION
      labels: %w[backend schema research brief-2]
    },
    {
      external_ref: "T6",
      title: "Portal listing API: property facts, dashboard, listing creation",
      description: <<~DESCRIPTION.strip,
        Schema/API: add the client-facing property facts `property_status`, `property_type`, `price_cents`, `bedrooms`, `bathrooms`, `square_feet`, `lot_acres`, `parking`, `year_built`, `mls_number`, and `mls_live_date`. Support the property vocabulary Coming Soon, For Sale, For Lease, Pending Sale, Pending Lease, For Rent, Sold, and List Off Market, with a property-created listing starting as a draft or booking request according to the approved lifecycle.

        Presentation boundary: derive a separate closed production lifecycle from appointments, delivery, and internal service state. Serialize only client language such as Coming Soon, Shoot Scheduled, Shoot Completed, In Progress, Editing, Ready for Review, Partially Delivered, Delivered/Complete, Action Required, and Live; internal workflow-column names and raw `listing.status` values must never leak. Retire `client_portal#show` after the new endpoint is equivalent and policy-authorized.

        Done when: API request and serializer specs cover authorization, creation, dashboard data, property/production status separation, and the no-internal-status guarantee, with capabilities included in the response.
      DESCRIPTION
      labels: %w[backend api portal schema brief-3]
    },
    {
      external_ref: "T7",
      title: "Account financials: credit, benefits, order codes",
      description: <<~DESCRIPTION.strip,
        Schema: add append-only `credit_transactions` with signed `amount_cents`, kind, reason, invoice linkage, and actor; calculate balance as the sum rather than storing a mutable balance column. Add `account_benefits` as the client-facing display beside pricing plans, with a single client account or customer team owner, rate basis points, order code, permanence, expiry, and active state.

        API and dashboard: expose current amount due across unpaid invoices/outstanding orders, credit or bonus balance, active/permanent discount, brokerage or referral/order code, and expiry when relevant. Apply credits and benefits server-side to commerce flows while leaving `pricing_plans` authoritative for order pricing; reject expired, inactive, cross-account, or unauthorized applications.

        Done when: financial mutations are auditable and append-only, money remains integer cents, access is covered by negative policy specs, and the first dashboard can answer what the client owes, has in credit, receives as a discount, and can use as a brokerage code without opening a deep settings page.
      DESCRIPTION
      labels: %w[backend api billing brief-3]
    },
    {
      external_ref: "T8",
      title: "Portal shell and dashboard home",
      description: <<~DESCRIPTION.strip,
        Frontend: create an isolated `app/(portal)/` route group with its own layout and stylesheet rather than extending the staff SPA's role logic. Use property-first HOME/LISTINGS/CREATE/PROMOTE/ACCOUNT navigation, minimal Help/AI/Notifications/Profile utilities, a compact welcome, and a prominent `Create New Listing` CTA. Meet the accessibility floor: 17px minimum body text, 44px targets, AA contrast in both themes, and no hover-only or icon-only primary actions. The dashboard brief's hierarchy is a visual reference, not a pixel-perfect mandate.

        Dashboard: build account summary (amount due, credit/bonus, discount/benefit, brokerage code), quick actions, active listing cards with prominent property imagery, address, property status, separate production status, media readiness, action-needed copy, and `Open Listing`. Add search by address/customer/order reference, simple status/date filters, upcoming shoots, and secondary recently delivered cards using one reusable `ListingCard` at the required densities. Add one `ServiceStatus` component that owns the closed client lifecycle and color mapping; raw internal status strings rendered outside it are a bug.

        Integration: consume the T6/T7 portal APIs and capabilities. Ship the AI assistant button plus a context payload for the current account/listing only; no AI answering backend is part of this task. Done when keyboard, responsive, loading, empty, forbidden, mobile two-column quick-action, vertical-card, and full-width CTA states are covered without turning the page into a dense SaaS table.
      DESCRIPTION
      labels: %w[frontend portal api brief-3]
    },
    {
      external_ref: "T9",
      title: "Listings index and listing workspace shell",
      description: <<~DESCRIPTION.strip,
        Frontend/API slice: build the portal listings index and a property-first listing workspace that gives a client one place to understand a property. Include the hero image/address, property facts and MLS context, customer/account context, production activity, appointments/shoot details, media, delivery, and the navigation seams for Overview, Media, Revisions, Property & MLS Details, Property Website, Marketing, Orders/Services, Payments, and Activity. The client should enter `123 Main Street`, not choose an internal order number. The listings-index screenshot from the dashboard brief is attached as a hierarchy and density reference.

        Reuse the dashboard's `ListingCard` and `ServiceStatus` components so cards and workspace headers use the same client vocabulary. Keep property marketing status separate from production status, surface action-required states without aggressive error styling, and fetch only listings the current account and team scope may view; do not expose internal board columns or unrelated organization records.

        Done when: the index links to a stable listing workspace, the workspace can be extended by media and revision slices, API/policy specs cover cross-account access, and the UI works at all supported card densities and mobile layouts.
      DESCRIPTION
      labels: %w[frontend backend portal brief-3]
    },
    {
      external_ref: "T10",
      title: "Account area: branding, social profiles, billing",
      description: <<~DESCRIPTION.strip,
        Schema: add one `brand_profile` per client account for display name, title, brokerage, office, phone, email, websites, bio, and social links for Instagram, Facebook, LinkedIn, YouTube, TikTok, X/Twitter, and future platforms. Add versioned `brand_assets` linked to media assets with slots such as primary logo, alternate logo, brokerage logo, headshot, and team logo; enforce one current asset per profile and slot with a partial unique index. The team, branding, and social-profiles brief is the source of these requirements.

        API/UI: build authorized account pages plus a compact dashboard Brand Profile card with preview, brokerage name, completeness/attention state, and `Manage Branding`. Replacing an asset creates a new version and flips `current`; it must not destroy the previous material. Current profile data must be reusable by future property websites, marketing materials, promotions, social content, and feature sheets, while older versions remain associated with historical output. Keep organization/admin and client-account boundaries explicit, and keep pricing-plan authority separate from display settings.

        Done when: clients can answer what logo/headshot/social data is active and whether future materials will use it, old versions remain recoverable, current-slot conflicts are impossible at the database level, and policy specs prevent another account from reading or changing branding or billing data.
      DESCRIPTION
      labels: %w[frontend backend portal brief-1 brief-3]
    },
    {
      external_ref: "T11",
      title: "Client team management and permission scopes",
      description: <<~DESCRIPTION.strip,
        Access model: add client-team invitations and membership records with simple permission scopes for full account, listing-only, media, billing, and marketing access. A member may be limited to selected listings or granted account-wide access according to the approved scope vocabulary; invitation acceptance must not cross organization or client-account boundaries. These scopes and Team Settings behavior come from the team, branding, and social-profiles brief.

        API/UI: provide Team Settings listing, `Add Team Member`, invite, revoke, and scope-management endpoints plus an account settings panel that clearly shows who has access. Serialize capabilities for the current user, authorize every mutation on the server, and keep staff board permissions separate from client-team permissions.

        Done when: a client manager can answer who has account access and administer their own team, a scoped member sees only permitted listings/media/actions, expired or revoked invitations cannot be used, and negative policy/request specs prove cross-account access is denied.
      DESCRIPTION
      labels: %w[backend frontend security brief-1]
    },
    {
      external_ref: "T12",
      title: "Media page: per-service delivery and downloads",
      description: <<~DESCRIPTION.strip,
        Data/API: implement the `listing_services` and media-delivery boundary decided in T5. Keep every ordered service visible in the property workspace, including Photography, Video, Vertical Reel, Drone, Floor Plan, Matterport/3D Tour, Property Website assets, and Files. Each service must carry a client-safe type, production state, ETA when known, delivered timestamp, asset count, and links to its delivered `media_assets`; do not overload the old generic category.

        Frontend: build a property header with hero image/address/overall status and a `3 of 5 services ready` summary, followed by a production and delivery tracker and large service cards. Cards show service name, count, closed client status, ETA or delivery time, View/Watch/Download, and Request Changes. Add Download Ready Media/Download All Available without pretending that unfinished services are ready. Do not expose queued/rendering/worker/pipeline statuses or artificial percentages. The media-page screenshot from the media and revision brief is attached as a hierarchy reference.

        Done when: a client cannot see another account's assets or staff-only media, each service's delivery state is traceable to its assets, downloads use the existing storage/CDN boundary, and storage/migration behavior plus client-safe status serialization is covered by integration specs.
      DESCRIPTION
      labels: %w[backend frontend media brief-2]
    },
    {
      external_ref: "T13",
      title: "Revision threads, versioning and the staff queue",
      description: <<~DESCRIPTION.strip,
        Schema: add `revision_requests` with listing/service, opener, status, kind, ETA, cycle, and opened/closed timestamps; add `revision_messages` with visibility and attachments; add `revision_references` for selected media assets, video timecodes, floor/room/page locators, and notes. Enforce one open request per listing service with a partial unique index while allowing completed history. The media-page and revision-workflow brief is the source for this service-level conversation model.

        Workflow/API: let clients submit a service-level revision or pre-delivery message from a side panel/full-screen mobile composer without retyping the property or service. For Photography, support multi-select images with thumbnails and one shared request; for Video/Vertical Reel, timestamped comments; for Floor Plans, floor/room/page references; and for other services, the same contextual thread with precise asset references. Allow screenshots, reference photos, replacement logos, documents, and music references, and keep follow-up messages in the same thread.

        Lifecycle/UI: show Submitted, Reviewing, Revision in Progress, Updated Version Ready, Client Review, or Completed on the service card. Preserve the originally delivered version, let staff reply/ask questions/upload an updated version, prevent duplicate requests by changing Request Changes to Open Request/Continue Conversation, and let a later cycle reopen or create history after completion. Give staff ownership, queue, ETA, and audit history.

        Done when: open-request state is truthful, revision status participates in the delivery lifecycle, client/staff visibility is policy-scoped, asset versions remain inspectable, and request/message/reference mutations have negative authorization coverage.
      DESCRIPTION
      labels: %w[backend frontend media workflow brief-2]
    }
  ].freeze

  desc "Synchronize the client portal plan issues on each organization's selected board (BOARD_SLUG defaults to engineering)"
  task sync_plan_tasks: :environment do
    board_slug = ENV.fetch("BOARD_SLUG", "engineering")
    organizations = if ENV["ORGANIZATION_SLUG"].present?
      [ Organization.find_by!(slug: ENV["ORGANIZATION_SLUG"]) ]
    else
      Organization.all
    end

    organizations.each do |organization|
      board = organization.boards.find_by(slug: board_slug)
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
          listing_id: nil,
          position: task.persisted? ? task.position : position,
          status: completed ? completed_status : (definition[:status] || task.status.presence || default_status),
          completed_at: completed ? (task.completed_at || Time.current) : task.completed_at
        )
        task.save!

        label_position = board.board_labels.maximum(:position).to_i + 1
        labels = definition.fetch(:labels).map.with_index do |label_name, offset|
          label = board.board_labels.find_or_initialize_by(name: label_name)
          label.position = label_position + offset unless label.persisted?
          label.save!
          label
        end
        task.board_labels = labels
      end

      puts "Synchronized #{PLAN_TASKS.length} plan tasks on #{organization.slug}/#{board.slug}"
    end
  end
end

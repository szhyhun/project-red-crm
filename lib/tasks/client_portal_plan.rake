namespace :project_red do
  PLAN_TASKS = [
    {
      external_ref: "T1",
      title: "Protect every CRM action with server-side authorization",
      description: <<~DESCRIPTION.strip,
        What the user needs: Every person should see and change only the CRM records they are allowed to use. Staff should be able to work in the boards granted to them, clients should see only their own account and listings, and an unauthorized request should return a clear "not allowed" response. Hiding a button in the interface must never be the thing that protects the data.

        Technical proposal: Make Pundit the default boundary for every API request. Use a shared `view?`, `create?`, `update?`, `destroy?`, and `manage?` contract, serialize per-record capabilities plus the `/auth/me` capability map, and return structured 403 responses. Convert dashboard and client-portal guards to policies. Add route coverage so every action authorizes or declares an explicit skip for public, webhook, sign-up, or authentication endpoints.

        Done when: the frontend uses capabilities instead of role comparisons, displays the API's 403 message, and the server remains the final authorization boundary.
      DESCRIPTION
      labels: %w[backend frontend security],
      status: "in_progress"
    },
    {
      external_ref: "T2",
      title: "Create separate boards with clear team access",
      description: <<~DESCRIPTION.strip,
        What the user needs: An organization should be able to keep separate work queues such as Production and CRM Development. A manager should choose which people or groups can see and manage each board. Tasks and columns from one board must never appear on another board, and clients must not see internal boards.

        Technical proposal: Add first-class boards, user groups, and board memberships. Scope columns and tasks by `board_id`, allow listing-free internal tasks, and add board flags for `requires_listing` and `client_visible`. Provide board CRUD/archive, member/group management, and board-scoped column/task endpoints. Keep organization-visible and restricted-board rules explicit in policies and scopes.

        Done when: a user who cannot view a board receives no task data from it, task movement stays inside one board, and managers can administer board membership without changing staff permissions elsewhere.
      DESCRIPTION
      labels: %w[backend frontend schema security],
      completed: true
    },
    {
      external_ref: "T3",
      title: "Make issue details useful for planning and discussion",
      description: <<~DESCRIPTION.strip,
        What the user needs: Opening an issue should explain what needs to happen without forcing the team to hunt through a separate system. People should be able to read and edit the description, see status/priority/assignee/due date, select labels already configured for the board, keep a checklist, and discuss the work in comments. A comment may have replies, but replies cannot create another reply level.

        Technical proposal: Add task comments and checklist items with author/completion metadata, ordering, and timestamps. Store labels as board-owned records and assign only labels from the task's board. Add authorized create/update/delete endpoints, one-level comment replies, sanitized rich text, and a detail endpoint that returns full collections while board cards return counts only. B1 owns the attachment upload/storage flow.

        Done when: the issue detail is readable and editable, checklist completion is attributable, labels can be filtered on the board, reply nesting stops at one level, and every mutation follows the board access rules.
      DESCRIPTION
      labels: %w[backend frontend schema],
      completed: true
    },
    {
      external_ref: "T4",
      title: "Keep the Engineering board plan synchronized",
      description: <<~DESCRIPTION.strip,
        What the user needs: The Engineering board should contain one understandable issue for every agreed plan item, with useful titles, matching labels, and the correct workflow status. Running the plan sync again should refresh stale wording without creating duplicate issues or unexpectedly moving work that a person has already arranged.

        Technical proposal: Make `project_red:sync_plan_tasks` idempotently upsert T1–T13 and B1 by `external_ref` on the selected board. Sync title, human-first description, labels, and initial status; preserve existing positions and deliberate status changes on reruns. Fail clearly when the target board has no workflow columns or completed column.

        Done when: the board has exactly one issue for each plan item, the issue copy stays aligned with the source plan, and rerunning the sync is safe for every organization with an Engineering board.
      DESCRIPTION
      labels: %w[backend schema data brief-1 brief-2 brief-3],
      completed: true
    },
    {
      external_ref: "B1",
      title: "Add rich issue content and attachments",
      description: <<~DESCRIPTION.strip,
        What the user needs: An issue should be able to carry the material needed to understand and implement it. People should be able to format the description or comment, paste or drag in screenshots, photos, screen recordings, videos, and documents, preview what was attached, and remove or download an attachment without leaving the issue.

        Technical proposal: Store attachment metadata with organization, board, task, and comment ownership. Upload bytes to a dedicated private board-media S3 bucket behind the existing CDN/storage boundary and return authorized preview/download URLs, never raw bucket paths. Validate MIME type, size, filename, and upload completion; retain video metadata such as duration and poster/thumbnail where available. Provide upload progress, retry, preview, remove, and accessible caption/alt-text controls.

        Done when: issue descriptions and comments can carry safe rich content and media, failed uploads can be retried, and unauthorized users cannot infer or fetch an attachment. Request specs must cover board isolation and failed uploads.
      DESCRIPTION
      labels: %w[backend frontend schema security media],
      completed: true
    },
    {
      external_ref: "T5",
      title: "Define how each property service moves from order to delivery",
      description: <<~DESCRIPTION.strip,
        What the user needs: Before the client-facing Media page is built, the team needs one clear answer to a simple question: for a property, how do we show every ordered service - photography, video, drone, floor plan, 3D tour, website assets, and files - from the first appointment through delivery? The client should see honest stages and useful ETAs, including reshoots or extra work, without seeing internal pipeline jargon.

        Technical proposal: Time-box a decision between a dedicated `listing_services` record and an `order_item` state. Define how cancelled, reshoot, goodwill, and off-order services enter the workflow; whether service types are fixed or catalog-configurable; and a closed client-facing vocabulary for state and ETA. Evaluate a `listing_services` model with listing/order-item link, service type, production state, ETA, delivered timestamp, asset count, position, and metadata. Document Aryeo mapping and a safe migration from generic `media_assets.category` without breaking DeliveryArchive or the public property site.

        Product reference: CRM Client Portal - Media Page & Revision Workflow Design Brief. It requires every ordered service to remain visible, with statuses such as Upcoming Shoot, Editing, Ready for Review, and Delivered, and it explicitly rejects queued/rendering/pipeline language and artificial percentages.

        Done when: the written decision covers the data model, migration/API implications, status mapping, ETA rules, Aryeo mapping, and sized follow-up tasks for the Media and Revision work.
      DESCRIPTION
      labels: %w[backend schema research brief-2]
    },
    {
      external_ref: "T6",
      title: "Give clients a property-first listings API",
      description: <<~DESCRIPTION.strip,
        What the user needs: A client should be able to create a property and later find it by address, then see the facts that matter to a real-estate listing: status, price, MLS information, beds, baths, square footage, lot, parking, year built, and property type. Property marketing status such as For Sale must remain separate from the production status of the media work.

        Technical proposal: Add the client-facing property fields `property_status`, `property_type`, `price_cents`, `bedrooms`, `bathrooms`, `square_feet`, `lot_acres`, `parking`, `year_built`, `mls_number`, and `mls_live_date`. Support Coming Soon, For Sale, For Lease, Pending Sale, Pending Lease, For Rent, Sold, and List Off Market. Add authorized listing index/detail/create endpoints. Derive a separate closed production lifecycle from appointments, delivery, and service state; never serialize internal board column names or raw `listing.status` values to clients. Retire `client_portal#show` after the replacement is equivalent and policy-authorized.

        Product reference: CRM Client Portal - First Dashboard Page Design Brief. It says the product must be property/listing first rather than order first, and that property marketing status and production status should be shown separately.

        Done when: a client can create and retrieve a listing by property, API specs cover authorization and the dashboard data, and no internal status string leaks through the client serializer.
      DESCRIPTION
      labels: %w[backend api portal schema brief-3]
    },
    {
      external_ref: "T7",
      title: "Show clients what they owe and what benefits they have",
      description: <<~DESCRIPTION.strip,
        What the user needs: At a glance, a client should know how much they owe, whether they have account or bonus credit, what discount or partner benefit is active, and which brokerage/order code they can use. A zero balance should be reassuring and explicit, and temporary benefits should show when they expire. The client should not have to search through billing pages for this context.

        Technical proposal: Add append-only `credit_transactions` with signed integer cents and audit context, and calculate the balance from the ledger. Add `account_benefits` for discount rate, order/referral code, permanence, expiry, active state, and client-account/customer-team ownership. Expose amount due across unpaid invoices/outstanding orders, credit, active benefits, code, and expiry in the dashboard. Apply credits and benefits server-side while keeping `pricing_plans` authoritative for order pricing; reject expired, inactive, cross-account, or unauthorized use.

        Product reference: CRM Client Portal - First Dashboard Page Design Brief. It explicitly asks for Amount Due, Account Credit/Bonus Credit, active or permanent discount, brokerage/order code, and expiry near the first dashboard.

        Done when: financial mutations are auditable, money stays integer cents, negative policy specs cover account isolation, and the dashboard can answer all four questions without a deep settings click.
      DESCRIPTION
      labels: %w[backend api billing brief-3]
    },
    {
      external_ref: "T8",
      title: "Build a clear, property-first client home page",
      description: <<~DESCRIPTION.strip,
        What the user needs: Within a few seconds of signing in, the client should understand which properties they are working on, what is ready, what needs attention, what is coming up, and where to start a new listing. The page should feel calm and property-focused rather than like a dense software dashboard. Home, Listings, Create, Promote, and Account should be obvious, and important actions should remain easy on a phone.

        Technical proposal: Build an isolated `app/(portal)/` route group with its own layout and stylesheet. Add compact welcome and account-summary areas, prominent `Create New Listing`, property-first navigation, quick actions, active listing cards with hero imagery, address, marketing status, separate production status, media readiness, attention copy, and `Open Listing`. Add address/customer/order search, simple status/date filters, upcoming shoots, recently delivered cards, and reusable `ListingCard` and `ServiceStatus` components. Include Help/AI/Notifications/Profile utilities and send only the current account/listing context to the AI entry point; no answer backend is in scope. Use 17px body text, 44px targets, AA contrast, clear focus states, responsive card layouts, and no hover-only primary actions.

        Product reference: CRM Client Portal - First Dashboard Page Design Brief. It requires a property-first overview, visible account summary, quick actions, active listings, upcoming shoots, recently delivered work, simple navigation, and a mobile layout that is intentionally designed rather than merely shrunk.

        Done when: keyboard, loading, empty, forbidden, responsive, mobile quick-action, vertical-card, and full-width CTA states work without turning the page into a dense SaaS table.
      DESCRIPTION
      labels: %w[frontend portal api brief-3]
    },
    {
      external_ref: "T9",
      title: "Give each property one workspace for all its work",
      description: <<~DESCRIPTION.strip,
        What the user needs: Clicking a property should open one durable workspace for that property. From there the client should be able to find the address and facts, understand appointments and production progress, and reach media, revisions, property details, website, marketing, orders/services, payments, and activity without choosing an internal order number or losing the property context.

        Technical proposal: Build the portal listings index and stable property workspace route. Include hero image/address, property and MLS facts, customer/account context, production activity, appointments/shoot details, media/delivery, and navigation seams for Overview, Media, Revisions, Property & MLS Details, Property Website, Marketing, Orders/Services, Payments, and Activity. Reuse `ListingCard` and `ServiceStatus`; keep marketing and production status separate; fetch only listings allowed by the current account/team scope.

        Product reference: CRM Client Portal - First Dashboard Page Design Brief. It says the client should think "123 Main Street," not "Order #18482," and that every property should become its own workspace. The supplied listings-index screenshot is a hierarchy and density reference.

        Done when: the index opens a stable property workspace, media and revision slices have clear seams, cross-account access is denied, and the index/workspace work at supported card densities and mobile widths.
      DESCRIPTION
      labels: %w[frontend backend portal brief-3]
    },
    {
      external_ref: "T10",
      title: "Let clients manage their brand and social profiles once",
      description: <<~DESCRIPTION.strip,
        What the user needs: A client should upload a logo, headshot, brokerage/team logo, public contact details, and social links once. They should see what is active, preview it, replace it without deleting everything first, and know that future property websites, marketing materials, social content, and feature sheets will use the current information. Older assets should remain available for work that was already produced.

        Technical proposal: Add one `brand_profile` per client account for name, title, brokerage, office, phone, email, websites, bio, and Instagram, Facebook, LinkedIn, YouTube, TikTok, X/Twitter, and future social links. Add versioned `brand_assets` linked to media assets for primary/alternate/brokerage/team logos and headshot, with one current asset per profile/slot enforced by a partial unique index. Build authorized account pages and a compact dashboard Brand Profile card with preview, brokerage name, completeness/attention state, and `Manage Branding`. Replacing an asset creates a new current version without destroying history; future outputs read current profile data while historical outputs retain their old references.

        Product reference: Additional Dashboard Requirements - Team Settings, Branding & Social Profiles. It requires centralized client assets, previews, Replace/Update actions, social links, public contact information, a Brand Profile card, and historical versions that do not change when the current profile is updated.

        Done when: clients can answer what brand data is active and whether future materials will use it, old versions remain recoverable, current-slot conflicts are impossible, and another account cannot read or change the profile.
      DESCRIPTION
      labels: %w[frontend backend portal brief-1 brief-3]
    },
    {
      external_ref: "T11",
      title: "Let clients manage who can access their account",
      description: <<~DESCRIPTION.strip,
        What the user needs: An account owner should be able to see who has access, invite an assistant or co-agent, remove access, and choose a simple scope such as full account, listings only, media, billing, or marketing. A person with limited access should see only the listings and actions granted to them.

        Technical proposal: Add client-team invitations and membership records with account-wide or selected-listing scopes. Provide Team Settings listing, `Add Team Member`, invite, revoke, and scope-management endpoints. Serialize capabilities for the current user, authorize every mutation server-side, prevent cross-organization/client-account acceptance, and keep client-team permissions separate from staff board permissions.

        Product reference: Additional Dashboard Requirements - Team Settings, Branding & Social Profiles. It asks for a simple Team Settings area, visible members, an obvious `+ Add Team Member` action, and future-friendly full/listing/media/billing/marketing permission scopes.

        Done when: an account manager can administer their team, a scoped member sees only permitted listings/media/actions, expired or revoked invitations cannot be used, and negative policy/request specs prove cross-account access is denied.
      DESCRIPTION
      labels: %w[backend frontend security brief-1]
    },
    {
      external_ref: "T12",
      title: "Show every ordered service with status and downloads",
      description: <<~DESCRIPTION.strip,
        What the user needs: Inside a property, the client should see every service they ordered, even if it is not finished yet. Each card should answer what the service is, whether it is scheduled/in progress/ready/delivered, when it should be ready, how many assets exist, and what the client can do. Ready media should be easy to view or download, and the client should have a clear Request Changes action without being told that a worker or pipeline is running.

        Technical proposal: Implement the `listing_services` and media-delivery boundary decided in T5. Keep Photography, Video, Vertical Reel, Drone, Floor Plan, Matterport/3D Tour, Property Website assets, Files, and future services visible. Store client-safe type, production state, ETA, delivered timestamp, asset count, position, and links to delivered `media_assets`. Build a property header with hero/address/overall status and a `3 of 5 services ready` summary, a tracker, and reusable service cards with View/Watch/Download, Download Ready Media/Download All Available, and Request Changes. Never expose queued/rendering/worker/pipeline terms or invented percentages.

        Product reference: CRM Client Portal - Media Page & Revision Workflow Design Brief. It requires property-first service cards, client-friendly statuses and ETAs, every ordered service visible during production, ready-media downloads, and no artificial progress percentages. The supplied media-page screenshot is a hierarchy reference.

        Done when: a client cannot see another account's assets or staff-only media, every service state is traceable to its assets, downloads use the existing storage/CDN boundary, and client-safe serialization is covered by integration specs.
      DESCRIPTION
      labels: %w[backend frontend media brief-2]
    },
    {
      external_ref: "T13",
      title: "Let clients request and track changes by service",
      description: <<~DESCRIPTION.strip,
        What the user needs: A client should click Request Changes on the service that needs work and get a conversation that already knows the property and service. They should be able to select several photos, point to a video timestamp, identify a floor/room/page, or attach a screenshot/document, then send one clear request. Staff should be able to reply, ask questions, upload an updated version, and show whether the request is being reviewed or is ready for client review.

        Technical proposal: Add `revision_requests` for listing/service, opener, status, kind, ETA, cycle, and timestamps; `revision_messages` for visibility and attachments; and `revision_references` for selected assets, video timecodes, floor/room/page locators, and notes. Enforce one open request per listing/service while retaining completed history. Provide a contextual desktop side panel and mobile full-screen composer. Use multi-select thumbnails for Photography, timestamps for Video/Vertical Reel, locators for Floor Plans, and the same service context for other media. Keep follow-up messages in the same thread.

        Lifecycle/UI: show Submitted, Reviewing, Revision in Progress, Updated Version Ready, Client Review, or Completed on the service card. Preserve the originally delivered version, prevent duplicate open requests by changing Request Changes to Open Request/Continue Conversation, and let a later cycle reopen or create history after completion. Give staff ownership, queue, ETA, and audit history.

        Product reference: CRM Client Portal - Media Page & Revision Workflow Design Brief. It specifies one service-level thread per listing/service with asset-level references, attachments, status on the service card, version history, and no ticket per individual message or photo.

        Done when: the open-request state is truthful, revision status participates in delivery, client/staff visibility is policy-scoped, versions remain inspectable, and request/message/reference mutations have negative authorization coverage.
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

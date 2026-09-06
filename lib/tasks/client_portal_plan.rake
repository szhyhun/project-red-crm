namespace :project_red do
  PLAN_TASKS = [
    {
      external_ref: "T1",
      title: "Capability-based authorization, enforced by default",
      description: "Make Pundit authorization the default for API requests. Add the shared policy question set, capability serialization, session capabilities, route coverage, and explicit skips for public, webhook, and authentication endpoints.",
      labels: %w[backend frontend security]
    },
    {
      external_ref: "T2",
      title: "Multiple boards with per-person and per-group access",
      description: "Introduce first-class boards with board-scoped workflow columns and tasks. Support per-board visibility, direct and group memberships, and policy-scoped reads and writes so a user who cannot view a board cannot view its tasks.",
      labels: %w[backend frontend schema security]
    },
    {
      external_ref: "T3",
      title: "Task detail: comments, checklists, labels",
      description: "Add task detail interactions for comments, checklists, and labels. Keep task detail board-authorized and return counts on cards so the board remains lightweight.",
      labels: %w[backend frontend]
    },
    {
      external_ref: "T4",
      title: "Seed the Engineering board from these briefs",
      description: "Seed the Engineering board from the client portal briefs with idempotent T1–T13 records. Keep these engineering issues independent of listings and label them by area and brief.",
      labels: %w[backend schema data brief-1 brief-2 brief-3]
    },
    {
      external_ref: "T5",
      title: "Deliverable services design spike",
      description: "Time-box a deliverable-services research spike. Define service types, production states, ETAs, and the data model that Phase G depends on; produce sized follow-up work.",
      labels: %w[backend schema research]
    },
    {
      external_ref: "T6",
      title: "Portal listing API: property facts, dashboard, listing creation",
      description: "Build the portal listing API for property facts, dashboard metrics, listing creation, and the closed client-facing lifecycle vocabulary. Retire the hand-rolled client portal response when the new boundary is ready.",
      labels: %w[backend api portal schema]
    },
    {
      external_ref: "T7",
      title: "Account financials: credit, benefits, order codes",
      description: "Add account financials: credits, benefits, order codes, and the server-side rules for applying them to commerce flows.",
      labels: %w[backend api billing]
    },
    {
      external_ref: "T8",
      title: "Portal shell and dashboard home",
      description: "Build the client portal shell and dashboard home, including navigation, responsive layout, shared listing cards, service status presentation, and the AI assistant entry point and context payload.",
      labels: %w[frontend portal api]
    },
    {
      external_ref: "T9",
      title: "Listings index and listing workspace shell",
      description: "Build the listings index and listing workspace shell around property facts, customer context, production activity, appointments, media, and delivery.",
      labels: %w[frontend backend portal]
    },
    {
      external_ref: "T10",
      title: "Account area: branding, social profiles, billing",
      description: "Add the account area for branding, social profiles, and billing settings, with clear organization and client access boundaries.",
      labels: %w[frontend backend portal]
    },
    {
      external_ref: "T11",
      title: "Client team management and permission scopes",
      description: "Add client team management and permission scopes so account users can be invited and limited to the right listings, media, and actions.",
      labels: %w[backend frontend security]
    },
    {
      external_ref: "T12",
      title: "Media page: per-service delivery and downloads",
      description: "Build the media page with per-service delivery states, downloads, client visibility, and the storage and CDN boundary.",
      labels: %w[backend frontend media]
    },
    {
      external_ref: "T13",
      title: "Revision threads, versioning and the staff queue",
      description: "Build revision threads, versioning, and a staff queue so client feedback becomes trackable production work with clear ownership and history.",
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

      PLAN_TASKS.each_with_index do |definition, position|
        task = board.workflow_tasks.find_or_initialize_by(external_ref: definition.fetch(:external_ref))
        task.assign_attributes(
          organization:,
          title: definition.fetch(:title),
          description: definition.fetch(:description),
          labels: definition.fetch(:labels),
          listing_id: nil,
          position: task.persisted? ? task.position : position,
          status: task.status.presence || default_status
        )
        task.save!
      end

      puts "Synchronized #{PLAN_TASKS.length} plan tasks on #{organization.slug}/#{board.slug}"
    end
  end
end

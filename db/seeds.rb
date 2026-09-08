if Rails.env.production? && ENV["SEED_DEMO_DATA"] != "true"
  puts "Skipping demo data in production. Set SEED_DEMO_DATA=true to enable it explicitly."
else
  password = ENV.fetch("DEMO_PASSWORD", "ProjectRed123!")
  created = []
  now = Time.current.change(min: 0, sec: 0)

  # Seeds are intentionally additive. A rerun fills in anything missing from the
  # demo workspace without overwriting edits made while developing the UI.
  ensure_record = lambda do |scope, lookup, &block|
    record = scope.find_or_initialize_by(lookup)
    if record.new_record?
      block&.call(record)
      record.save!
      created << "#{record.class.name} #{record.id}"
    end
    record
  end

  ActiveRecord::Base.transaction do
    organization = ensure_record.call(Organization.all, slug: "project-red-demo") do |record|
      record.name = "ProjectRed Demo"
    end

    admin = ensure_record.call(User.all, email: "admin@projectred.local") do |record|
      record.assign_attributes(
        organization:, name: "Sasha Admin", role: :organization_admin, status: :active,
        password:, password_confirmation: password
      )
    end

    manager = ensure_record.call(User.all, email: "manager@projectred.local") do |record|
      record.assign_attributes(
        organization:, name: "Taylor Producer", role: :manager, status: :active,
        password:, password_confirmation: password
      )
    end

    producer = ensure_record.call(User.all, email: "producer@projectred.local") do |record|
      record.assign_attributes(
        organization:, name: "Jordan Producer", role: :production_staff, status: :active,
        password:, password_confirmation: password
      )
    end

    editor = ensure_record.call(User.all, email: "editor@projectred.local") do |record|
      record.assign_attributes(
        organization:, name: "Casey Editor", role: :production_staff, status: :active,
        password:, password_confirmation: password
      )
    end

    coordinator = ensure_record.call(User.all, email: "coordinator@projectred.local") do |record|
      record.assign_attributes(
        organization:, name: "Morgan Coordinator", role: :manager, status: :active,
        password:, password_confirmation: password
      )
    end

    client_accounts = {}
    [
      {
        key: :oak_bay, name: "Oak Bay Realty", kind: :brokerage,
        email: "avery@oakbayrealty.example", phone: "+1 250 555 0142",
        brokerage_name: "Oak Bay Realty"
      },
      {
        key: :coastal, name: "Coastal Homes", kind: :team,
        email: "priya@coastalhomes.example", phone: "+1 250 555 0188",
        brokerage_name: "Coastal Homes"
      },
      {
        key: :west_coast, name: "West Coast Estates", kind: :agent,
        email: "jamie@westcoastestates.example", phone: "+1 604 555 0127",
        brokerage_name: "West Coast Estates"
      }
    ].each do |definition|
      client_accounts[definition.fetch(:key)] = ensure_record.call(
        organization.client_accounts, name: definition.fetch(:name)
      ) do |record|
        record.assign_attributes(
          kind: definition.fetch(:kind), email: definition.fetch(:email),
          phone: definition.fetch(:phone), brokerage_name: definition.fetch(:brokerage_name)
        )
      end
    end

    client_users = {}
    [
      { key: :avery, email: "client@projectred.local", name: "Avery Agent", role: :client_admin, account: :oak_bay },
      { key: :priya, email: "priya@projectred.local", name: "Priya Shah", role: :client_admin, account: :coastal },
      { key: :jamie, email: "jamie@projectred.local", name: "Jamie Chen", role: :client_member, account: :west_coast }
    ].each do |definition|
      client_users[definition.fetch(:key)] = ensure_record.call(User.all, email: definition.fetch(:email)) do |record|
        record.assign_attributes(
          organization:, name: definition.fetch(:name), role: definition.fetch(:role), status: :active,
          password:, password_confirmation: password
        )
      end

      ensure_record.call(
        ClientMembership.all,
        client_account: client_accounts.fetch(definition.fetch(:account)), user: client_users.fetch(definition.fetch(:key))
      ) do |record|
        record.role = :admin
      end
    end

    production_board = ensure_record.call(organization.boards, slug: "production") do |record|
      record.assign_attributes(
        name: "Production", kind: :production, visibility: :organization,
        requires_listing: true, client_visible: true, position: 0, created_by: admin
      )
    end

    development_board = ensure_record.call(organization.boards, slug: "crm-development") do |record|
      record.assign_attributes(
        name: "CRM Development", description: "Internal product and engineering work",
        kind: :internal, visibility: :organization, requires_listing: false,
        client_visible: false, position: 1, created_by: admin
      )
    end

    [ production_board, development_board ].each do |board|
      WorkflowColumn::DEFAULTS.each do |attributes|
        ensure_record.call(board.workflow_columns, key: attributes.fetch(:key)) do |record|
          record.assign_attributes(attributes.merge(organization: organization))
        end
      end
    end

    production_labels = {}
    [
      [ "client-review", "#e8f0ff" ],
      [ "media", "#e8f7ed" ],
      [ "editing", "#f1eafa" ],
      [ "urgent", "#fde7e3" ],
      [ "delivery", "#fbf4d7" ]
    ].each_with_index do |(name, color), position|
      production_labels[name] = ensure_record.call(production_board.board_labels, name:) do |record|
        record.assign_attributes(color:, position:)
      end
    end

    development_labels = {}
    [
      [ "backend", "#e8f7ed" ],
      [ "frontend", "#e8f0ff" ],
      [ "security", "#f1eafa" ]
    ].each_with_index do |(name, color), position|
      development_labels[name] = ensure_record.call(development_board.board_labels, name:) do |record|
        record.assign_attributes(color:, position:)
      end
    end

    listing_definitions = [
      {
        public_slug: "111-oak-bay-avenue", client_account: client_accounts.fetch(:oak_bay),
        status: :in_production, property_status: :for_sale,
        address_line_1: "111 Oak Bay Avenue", city: "Victoria", province: "BC", postal_code: "V8R 1C4",
        square_feet: 2450, bedrooms: 3, bathrooms: 2.5, price_cents: 129_500_000,
        property_type: "Detached home", parking: "Double garage", year_built: 1998,
        lot_acres: 0.18, scheduled_at: now + 2.days, tags: %w[premium photography video]
      },
      {
        public_slug: "42-fernwood-road", client_account: client_accounts.fetch(:coastal),
        status: :booked, property_status: :for_sale,
        address_line_1: "42 Fernwood Road", city: "Victoria", province: "BC", postal_code: "V8T 2A5",
        square_feet: 1820, bedrooms: 3, bathrooms: 2.0, price_cents: 89_900_000,
        property_type: "Townhouse", parking: "Carport", year_built: 2012,
        lot_acres: 0.04, scheduled_at: now + 4.days, tags: %w[photo floor-plan]
      },
      {
        public_slug: "780-beach-drive", client_account: client_accounts.fetch(:oak_bay),
        status: :delivered, delivery_status: :delivered, property_status: :sold,
        address_line_1: "780 Beach Drive", city: "Oak Bay", province: "BC", postal_code: "V8S 2M4",
        square_feet: 3150, bedrooms: 4, bathrooms: 3.5, price_cents: 185_000_000,
        property_type: "Waterfront home", parking: "Three-car garage", year_built: 2005,
        lot_acres: 0.31, delivered_at: now - 21.days, mls_live_date: now.to_date - 18.days,
        tags: %w[delivered showcase]
      },
      {
        public_slug: "15-cedar-lane", client_account: client_accounts.fetch(:west_coast),
        status: :review, property_status: :pending_sale,
        address_line_1: "15 Cedar Lane", city: "Saanich", province: "BC", postal_code: "V8N 1P7",
        square_feet: 2100, bedrooms: 4, bathrooms: 2.5, price_cents: 107_500_000,
        property_type: "Rancher", parking: "Double garage", year_built: 1987,
        lot_acres: 0.22, scheduled_at: now - 1.day, tags: %w[client-review revision]
      },
      {
        public_slug: "210-harbour-view", client_account: client_accounts.fetch(:coastal),
        status: :quoted, property_status: :coming_soon,
        address_line_1: "210 Harbour View", city: "Esquimalt", province: "BC", postal_code: "V9A 3S1",
        square_feet: 1400, bedrooms: 2, bathrooms: 2.0, price_cents: 69_900_000,
        property_type: "Condominium", parking: "Underground stall", year_built: 2020,
        tags: %w[quote upcoming]
      }
    ]

    listings = {}
    listing_definitions.each do |definition|
      slug = definition.fetch(:public_slug)
      listings[slug] = ensure_record.call(organization.listings, public_slug: slug) do |record|
        record.assign_attributes(definition.except(:public_slug))
      end
    end

    {
      "111-oak-bay-avenue" => [ [ manager, "manager" ], [ producer, "photographer" ], [ editor, "editor" ] ],
      "42-fernwood-road" => [ [ manager, "manager" ], [ producer, "photographer" ] ],
      "780-beach-drive" => [ [ manager, "manager" ], [ editor, "editor" ] ],
      "15-cedar-lane" => [ [ coordinator, "manager" ], [ editor, "editor" ] ],
      "210-harbour-view" => [ [ coordinator, "manager" ] ]
    }.each do |slug, assignments|
      assignments.each do |user, role|
        ensure_record.call(listings.fetch(slug).listing_assignments, user:, role:) { }
      end
    end

    product_definitions = [
      {
        slug: "premium-photo-video-package", title: "Premium Photo + Video Package", kind: :package,
        description: "Professional photography, cinematic video, and a property website.",
        capabilities: %w[photo.premium video.premium listing.website],
        variants: [
          { external_id: "premium-under-2000", title: "Up to 2,000 sq ft", price_cents: 39_900, duration_minutes: 150, sqft_min: 0, sqft_max: 2000 },
          { external_id: "premium-2001-3500", title: "2,001–3,500 sq ft", price_cents: 54_900, duration_minutes: 180, sqft_min: 2001, sqft_max: 3500 }
        ]
      },
      {
        slug: "standard-photo-package", title: "Standard Photo Package", kind: :package,
        description: "Bright, consistent listing photography for everyday property marketing.",
        capabilities: %w[photo.standard],
        variants: [
          { external_id: "standard-under-2000", title: "Up to 2,000 sq ft", price_cents: 19_900, duration_minutes: 90, sqft_min: 0, sqft_max: 2000 },
          { external_id: "standard-2001-3500", title: "2,001–3,500 sq ft", price_cents: 24_900, duration_minutes: 120, sqft_min: 2001, sqft_max: 3500 }
        ]
      },
      {
        slug: "standard-property-photography", title: "Standard Property Photography", kind: :service,
        description: "A complete set of bright, consistent interior and exterior property photos.",
        capabilities: %w[photo.standard], deliverable_type: "photography", sla_days: 2,
        variants: [
          { external_id: "photography-under-2000", title: "Up to 2,000 sq ft", price_cents: 29_900, duration_minutes: 90, sqft_min: 0, sqft_max: 2000 },
          { external_id: "photography-2001-3500", title: "2,001–3,500 sq ft", price_cents: 39_900, duration_minutes: 120, sqft_min: 2001, sqft_max: 3500 }
        ]
      },
      {
        slug: "cinematic-property-video", title: "Cinematic Property Video", kind: :service,
        description: "A polished walkthrough video for the property's marketing campaign.",
        capabilities: %w[video.premium], deliverable_type: "video", sla_days: 3,
        variants: [
          { external_id: "video-under-2000", title: "Up to 2,000 sq ft", price_cents: 39_900, duration_minutes: 120, sqft_min: 0, sqft_max: 2000 },
          { external_id: "video-2001-3500", title: "2,001–3,500 sq ft", price_cents: 49_900, duration_minutes: 150, sqft_min: 2001, sqft_max: 3500 }
        ]
      },
      {
        slug: "floor-plan-measurements", title: "Floor Plan and Measurements", kind: :service,
        description: "Measured floor plan with room labels and dimensions.", capabilities: %w[floorplan.standard],
        variants: [ { external_id: "floorplan-standard", title: "Standard floor plan", price_cents: 12_500, duration_minutes: 45 } ]
      },
      {
        slug: "twilight-photography", title: "Twilight Photography", kind: :addon,
        description: "A twilight exterior set for premium marketing campaigns.", capabilities: %w[photo.twilight],
        variants: [ { external_id: "twilight-standard", title: "Twilight set", price_cents: 14_900, duration_minutes: 45 } ]
      },
      {
        slug: "property-website", title: "Property Website", kind: :service,
        description: "Branded property page with listing details, media, and contact links.", capabilities: %w[listing.website],
        variants: [ { external_id: "website-30-days", title: "30-day website", price_cents: 9_900, duration_minutes: 30 } ]
      }
    ]

    products = {}
    variants = {}
    product_definitions.each do |definition|
      product = ensure_record.call(organization.products, slug: definition.fetch(:slug)) do |record|
        record.assign_attributes(
          title: definition.fetch(:title), kind: definition.fetch(:kind),
          description: definition.fetch(:description), capabilities: definition.fetch(:capabilities),
          active: true, bundle_candidate: definition.fetch(:kind) == :package,
          deliverable_type: definition[:deliverable_type], sla_days: definition[:sla_days]
        )
      end
      products[definition.fetch(:slug)] = product

      definition.fetch(:variants).each do |variant_definition|
        variant_key = variant_definition.fetch(:external_id)
        variants[variant_key] = ensure_record.call(product.product_variants, external_id: variant_key) do |record|
          record.assign_attributes(variant_definition)
        end
      end
    end

    # Keep the demo catalog useful on a fresh install and on an additive seed
    # rerun. Package contents are relational records, so the package editor and
    # approval workflow exercise the same component model as real catalog data.
    [
      {
        package: "premium-photo-video-package",
        services: [ "standard-property-photography", "cinematic-property-video", "property-website" ]
      },
      {
        package: "standard-photo-package",
        services: [ "standard-property-photography" ]
      }
    ].each do |definition|
      definition.fetch(:services).each_with_index do |service_slug, position|
        ensure_record.call(organization.product_components, package_product: products.fetch(definition.fetch(:package)),
                           service_product: products.fetch(service_slug)) do |record|
          record.assign_attributes(quantity: 1, position:)
        end
      end
    end

    order_definitions = [
      {
        key: :oak_bay_active, listing: listings.fetch("111-oak-bay-avenue"), client_account: client_accounts.fetch(:oak_bay),
        status: :invoiced, payment_mode: :pay_later, fulfillment_status: :unfulfilled,
        items: [ [ "premium-2001-3500", 1 ], [ "floorplan-standard", 1 ] ]
      },
      {
        key: :fernwood_paid, listing: listings.fetch("42-fernwood-road"), client_account: client_accounts.fetch(:coastal),
        status: :paid, payment_mode: :pay_now, fulfillment_status: :partially_fulfilled,
        items: [ [ "standard-under-2000", 1 ], [ "twilight-standard", 1 ] ]
      },
      {
        key: :beach_delivered, listing: listings.fetch("780-beach-drive"), client_account: client_accounts.fetch(:oak_bay),
        status: :paid, payment_mode: :pay_later, fulfillment_status: :fulfilled,
        items: [ [ "premium-2001-3500", 1 ], [ "website-30-days", 1 ] ]
      },
      {
        key: :cedar_draft, listing: listings.fetch("15-cedar-lane"), client_account: client_accounts.fetch(:west_coast),
        status: :draft, payment_mode: :pay_later, fulfillment_status: :unfulfilled,
        items: [ [ "standard-2001-3500", 1 ], [ "floorplan-standard", 1 ] ]
      }
    ]

    orders = {}
    order_definitions.each do |definition|
      order_scope = organization.orders.where(
        listing: definition.fetch(:listing), client_account: definition.fetch(:client_account)
      )
      order = order_scope.first
      order_was_new = order.blank?
      if order_was_new
        order = order_scope.build
        order.assign_attributes(
          status: definition.fetch(:status), payment_mode: definition.fetch(:payment_mode),
          fulfillment_status: definition.fetch(:fulfillment_status), currency: "cad", source: "crm"
        )
        order.save!
        created << "Order #{order.id}"
      end

      definition.fetch(:items).each do |variant_key, quantity|
        variant = variants.fetch(variant_key)
        ensure_record.call(order.order_items, product_variant: variant) do |record|
          record.assign_attributes(
            product: variant.product, title: variant.title, quantity:,
            unit_price_cents: variant.price_cents, total_cents: variant.price_cents * quantity
          )
        end
      end

      if order_was_new
        order.recalculate_totals!
        order.save!
      end
      orders[definition.fetch(:key)] = order
    end

    [
      { number: "PR-DEMO-001", order: orders.fetch(:oak_bay_active), status: :sent, due_on: now.to_date + 14.days },
      { number: "PR-DEMO-002", order: orders.fetch(:fernwood_paid), status: :paid, due_on: now.to_date - 2.days, paid_at: now - 1.day },
      { number: "PR-DEMO-003", order: orders.fetch(:beach_delivered), status: :paid, due_on: now.to_date - 30.days, paid_at: now - 25.days },
      { number: "PR-DEMO-004", order: orders.fetch(:cedar_draft), status: :draft, due_on: now.to_date + 30.days }
    ].each do |definition|
      order = definition.fetch(:order)
      status = definition.fetch(:status)
      ensure_record.call(organization.invoices, number: definition.fetch(:number)) do |record|
        record.assign_attributes(
          client_account: order.client_account, listing: order.listing, order:, status:, currency: "cad",
          subtotal_cents: order.subtotal_cents, total_cents: order.total_cents,
          balance_due_cents: status == :paid ? 0 : order.total_cents,
          due_on: definition.fetch(:due_on), sent_at: status == :draft ? nil : now,
          paid_at: definition[:paid_at]
        )
      end
    end

    appointment_definitions = [
      {
        listing: listings.fetch("111-oak-bay-avenue"), order: orders.fetch(:oak_bay_active), assigned_user: producer,
        status: :confirmed, request_status: :not_requested, starts_at: now + 2.days + 10.hours,
        ends_at: now + 2.days + 12.hours, notes: "Interior and exterior photo/video session"
      },
      {
        listing: listings.fetch("42-fernwood-road"), order: orders.fetch(:fernwood_paid), assigned_user: producer,
        status: :scheduled, request_status: :not_requested, starts_at: now + 4.days + 13.hours,
        ends_at: now + 4.days + 15.hours, notes: "Standard photo session"
      },
      {
        listing: listings.fetch("780-beach-drive"), order: orders.fetch(:beach_delivered), assigned_user: editor,
        status: :completed, request_status: :approved, starts_at: now - 21.days + 9.hours,
        ends_at: now - 21.days + 11.hours, completed_at: now - 20.days, notes: "Delivered media review"
      },
      {
        listing: listings.fetch("15-cedar-lane"), order: orders.fetch(:cedar_draft), assigned_user: coordinator,
        status: :postponed, request_status: :requested, starts_at: now + 6.days + 11.hours,
        ends_at: now + 6.days + 13.hours, notes: "Customer requested a different time"
      }
    ]

    appointment_definitions.each do |definition|
      appointment = ensure_record.call(organization.appointments, listing: definition.fetch(:listing)) do |record|
        record.assign_attributes(definition)
      end

      [ definition.fetch(:assigned_user), manager ].uniq.each do |user|
        ensure_record.call(appointment.appointment_team_members, user:) { }
      end
    end

    ensure_task = lambda do |board:, listing:, title:, status:, priority:, position:, assignee:, reporter:, customer_visible:, due_at:, description:, labels:, checklist:, comment: nil, reply: nil|
      task = ensure_record.call(board.workflow_tasks.where(listing:), title:) do |record|
        record.assign_attributes(
          organization:, board:, listing:, status:, priority:, position:, assignee:, reporter:,
          customer_visible:, due_at:, description:
        )
      end

      label_catalog = board == production_board ? production_labels : development_labels
      labels.each do |label_name|
        ensure_record.call(task.workflow_task_labels, board_label: label_catalog.fetch(label_name)) { }
      end

      checklist.each_with_index do |checklist_title, checklist_position|
        ensure_record.call(task.task_checklist_items, title: checklist_title) do |record|
          record.position = checklist_position
        end
      end

      if comment.present?
        parent = ensure_record.call(task.task_comments, author: manager, body: comment) { }
        ensure_record.call(task.task_comments, author: assignee || editor, body: reply, parent_comment: parent) if reply.present?
      end

      task
    end

    task_definitions = [
      {
        board: production_board, listing: listings.fetch("111-oak-bay-avenue"), title: "Confirm access details",
        status: :todo, priority: :high, position: 0, assignee: coordinator, reporter: manager,
        customer_visible: false, due_at: now + 1.day,
        description: "Confirm lockbox access, parking instructions, and the customer's preferred arrival window.",
        labels: %w[client-review], checklist: [ "Confirm access instructions", "Share arrival window with the crew" ],
        comment: "The client asked us to use the side entrance.", reply: "Added the access note to the appointment."
      },
      {
        board: production_board, listing: listings.fetch("111-oak-bay-avenue"), title: "Capture photo and video",
        status: :in_progress, priority: :urgent, position: 0, assignee: producer, reporter: manager,
        customer_visible: false, due_at: now + 2.days,
        description: "Complete the scheduled interior, exterior, and twilight coverage for the listing.",
        labels: %w[media urgent], checklist: [ "Photograph every room", "Record exterior video", "Upload source files" ],
        comment: "Weather is clear for the exterior session."
      },
      {
        board: production_board, listing: listings.fetch("111-oak-bay-avenue"), title: "Edit final gallery",
        status: :todo, priority: :normal, position: 1, assignee: editor, reporter: manager,
        customer_visible: false, due_at: now + 5.days,
        description: "Select, edit, and export the final gallery and video review cut.",
        labels: %w[editing media], checklist: [ "Cull source images", "Apply the project preset", "Export review gallery" ]
      },
      {
        board: production_board, listing: listings.fetch("111-oak-bay-avenue"), title: "Client review",
        status: :blocked, priority: :normal, position: 0, assignee: manager, reporter: manager,
        customer_visible: true, due_at: now + 7.days,
        description: "Collect customer feedback on the review gallery before final delivery.",
        labels: %w[client-review], checklist: [ "Send review link", "Record requested changes" ]
      },
      {
        board: production_board, listing: listings.fetch("42-fernwood-road"), title: "Prepare shoot kit",
        status: :todo, priority: :normal, position: 2, assignee: producer, reporter: manager,
        customer_visible: false, due_at: now + 3.days,
        description: "Prepare camera, lighting, and floor-plan equipment for the Fernwood appointment.",
        labels: %w[media], checklist: [ "Charge batteries", "Pack floor-plan equipment" ]
      },
      {
        board: production_board, listing: listings.fetch("15-cedar-lane"), title: "Apply customer revisions",
        status: :in_progress, priority: :high, position: 1, assignee: editor, reporter: coordinator,
        customer_visible: true, due_at: now + 2.days,
        description: "Apply the requested edits to the Cedar Lane gallery and return it for customer review.",
        labels: %w[editing client-review], checklist: [ "Review customer notes", "Export revised gallery" ],
        comment: "The customer requested a warmer living-room edit.", reply: "I will include that change in the next review export."
      },
      {
        board: production_board, listing: listings.fetch("780-beach-drive"), title: "Deliver final media",
        status: :done, priority: :normal, position: 0, assignee: editor, reporter: manager,
        customer_visible: true, due_at: now - 18.days,
        description: "Publish the approved media package to the customer delivery workspace.",
        labels: %w[delivery media], checklist: [ "Verify downloads", "Mark delivery ready" ]
      },
      {
        board: development_board, listing: nil, title: "Review Aryeo import mapping",
        status: :in_progress, priority: :high, position: 0, assignee: manager, reporter: admin,
        customer_visible: false, due_at: now + 3.days,
        description: "Confirm that imported listings, customer accounts, orders, and media retain their source relationships.",
        labels: %w[backend], checklist: [ "Run a sample import", "Check listing media links" ]
      },
      {
        board: development_board, listing: nil, title: "Document payment provider setup",
        status: :todo, priority: :normal, position: 1, assignee: admin, reporter: admin,
        customer_visible: false, due_at: now + 10.days,
        description: "Document the provider configuration needed to issue invoices and accept customer payments.",
        labels: %w[backend security], checklist: [ "List required credentials", "Add production verification steps" ]
      }
    ]

    task_definitions.each { |definition| ensure_task.call(**definition) }

    conversation_definitions = [
      {
        listing: listings.fetch("111-oak-bay-avenue"), client_account: client_accounts.fetch(:oak_bay),
        subject: "111 Oak Bay Avenue production", users: [ [ manager, :manager ], [ client_users.fetch(:avery), :participant ] ],
        messages: [ [ manager, "Your shoot is confirmed. We will post production updates here." ], [ client_users.fetch(:avery), "Thanks. Please let me know when the review gallery is ready." ] ]
      },
      {
        listing: listings.fetch("15-cedar-lane"), client_account: client_accounts.fetch(:west_coast),
        subject: "Cedar Lane revisions", users: [ [ coordinator, :manager ], [ editor, :participant ], [ client_users.fetch(:jamie), :participant ] ],
        messages: [ [ coordinator, "We received your requested gallery changes and assigned them to Casey." ], [ client_users.fetch(:jamie), "Thank you. The warmer living-room edit is the main priority." ] ]
      }
    ]

    conversation_definitions.each do |definition|
      conversation = ensure_record.call(
        organization.conversations,
        client_account: definition.fetch(:client_account), kind: :client
      ) do |record|
        record.assign_attributes(listing: nil, subject: definition.fetch(:subject), last_message_at: now)
      end

      definition.fetch(:users).each do |user, role|
        ensure_record.call(conversation.conversation_memberships, user:) { |record| record.role = role }
      end

      definition.fetch(:messages).each do |author, body|
        ensure_record.call(conversation.messages, author:, body:) { }
      end
    end

    internal_conversation = ensure_record.call(
      organization.conversations, kind: :internal, listing: nil, client_account: nil
    ) do |record|
      record.assign_attributes(subject: "Production standup", last_message_at: now, retention_period: :six_months)
    end

    [ [ admin, :manager ], [ manager, :manager ], [ producer, :participant ], [ editor, :participant ] ].each do |user, role|
      ensure_record.call(internal_conversation.conversation_memberships, user:) { |record| record.role = role }
    end
    [ [ manager, "Fernwood shoot is booked for Thursday." ], [ producer, "I will bring the floor-plan kit." ],
      [ editor, "I will review the Oak Bay source files after the shoot." ] ].each do |author, body|
      ensure_record.call(internal_conversation.messages, author:, body:) { }
    end
  end

  puts "ProjectRed demo seed complete (#{created.length} records created)."
  puts "Demo password: #{password}"
  puts "Admin: admin@projectred.local"
  puts "Manager: manager@projectred.local"
  puts "Producer: producer@projectred.local"
  puts "Editor: editor@projectred.local"
  puts "Customer: client@projectred.local"
  puts "Workspace: 1 organization, 2 boards, 5 listings, 9 tasks, 7 products"
end

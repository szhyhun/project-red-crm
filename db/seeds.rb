if Rails.env.production? && ENV["SEED_DEMO_DATA"] != "true"
  puts "Skipping demo data in production. Set SEED_DEMO_DATA=true to enable it explicitly."
else
  password = ENV.fetch("DEMO_PASSWORD", "ProjectRed123!")
  created = []

  find_or_create = lambda do |scope, attributes, &block|
    record = scope.find_or_initialize_by(attributes)
    if record.new_record?
      block&.call(record)
      record.save!
      created << "#{record.class.name} #{record.id}"
    end
    record
  end

  ActiveRecord::Base.transaction do
    organization = find_or_create.call(Organization.all, slug: "project-red-demo") do |record|
      record.name = "ProjectRed Demo"
    end

    admin = find_or_create.call(User.all, email: "admin@projectred.local") do |record|
      record.assign_attributes(
        organization:, name: "Sasha Admin", role: :organization_admin, status: :active,
        password:, password_confirmation: password
      )
    end

    staff = find_or_create.call(User.all, email: "producer@projectred.local") do |record|
      record.assign_attributes(
        organization:, name: "Taylor Producer", role: :production_staff, status: :active,
        password:, password_confirmation: password
      )
    end

    client = find_or_create.call(organization.client_accounts, name: "Avery Agent") do |record|
      record.assign_attributes(
        kind: :agent, email: "client@projectred.local", phone: "+1 250 555 0142",
        brokerage_name: "Oak Bay Realty"
      )
    end

    client_user = find_or_create.call(User.all, email: "client@projectred.local") do |record|
      record.assign_attributes(
        organization:, name: "Avery Agent", role: :client_admin, status: :active,
        password:, password_confirmation: password
      )
    end

    find_or_create.call(ClientMembership.all, client_account: client, user: client_user) do |record|
      record.role = :admin
    end

    listing = find_or_create.call(organization.listings, public_slug: "111-oak-bay-avenue") do |record|
      record.assign_attributes(
        client_account: client, status: :in_production, address_line_1: "111 Oak Bay Avenue",
        city: "Victoria", province: "BC", postal_code: "V8R 1C4", square_feet: 2450,
        bedrooms: 3, bathrooms: 2.5
      )
    end

    shoot_start = Time.zone.tomorrow.to_time.change(hour: 10)
    find_or_create.call(organization.appointments, listing:) do |record|
      record.assign_attributes(
        assigned_user: staff, status: :confirmed, starts_at: shoot_start,
        ends_at: shoot_start + 90.minutes, notes: "Premium photo and video shoot",
        calendar_color: "#3d0cff"
      )
    end

    [
      ["Confirm access details", "intake", :todo, :high, 0, admin, false],
      ["Capture photo and video", "shoot", :in_progress, :urgent, 0, staff, false],
      ["Edit final gallery", "post_production", :todo, :normal, 1, staff, false],
      ["Client review", "review", :blocked, :normal, 0, admin, true]
    ].each do |title, stage, status, priority, position, assignee, customer_visible|
      find_or_create.call(listing.workflow_tasks, title:) do |record|
        record.assign_attributes(
          organization:, stage:, status:, priority:, position:, assignee:, customer_visible:,
          due_at: shoot_start + 1.day
        )
      end
    end

    product = find_or_create.call(organization.products, slug: "premium-listing-package") do |record|
      record.assign_attributes(
        title: "Premium Listing Package", kind: :package,
        description: "Premium photos, video, floor plan, and property website",
        active: true, bundle_candidate: true,
        capabilities: %w[photo.premium video.premium floorplan.standard listing.website]
      )
    end

    variant = find_or_create.call(product.product_variants, external_id: "demo-2000-2999") do |record|
      record.assign_attributes(
        title: "2,000-2,999 sq ft", price_cents: 54_900, duration_minutes: 120,
        sqft_min: 2000, sqft_max: 2999, active: true
      )
    end

    order = find_or_create.call(organization.orders, listing:, client_account: client) do |record|
      record.assign_attributes(
        status: :submitted, payment_mode: :pay_later, currency: "cad", source: "crm",
        subtotal_cents: 54_900, total_cents: 54_900
      )
    end

    find_or_create.call(order.order_items, product:, product_variant: variant) do |record|
      record.assign_attributes(
        title: product.title, quantity: 1, unit_price_cents: 54_900, total_cents: 54_900
      )
    end

    find_or_create.call(organization.invoices, number: "PR-DEMO-001") do |record|
      record.assign_attributes(
        client_account: client, listing:, order:, status: :sent, currency: "cad",
        subtotal_cents: 54_900, total_cents: 54_900, balance_due_cents: 54_900,
        due_on: 14.days.from_now.to_date, sent_at: Time.current
      )
    end

    conversation = find_or_create.call(organization.conversations, listing:, client_account: client, kind: :client) do |record|
      record.assign_attributes(subject: "111 Oak Bay Avenue production", last_message_at: Time.current)
    end

    find_or_create.call(conversation.conversation_memberships, user: admin) { |record| record.role = :manager }
    find_or_create.call(conversation.conversation_memberships, user: client_user) { |record| record.role = :participant }
    find_or_create.call(conversation.messages, author: admin, body: "Your shoot is confirmed. We will post production updates here.")
  end

  puts "ProjectRed demo seed complete (#{created.length} records created)."
  puts "Admin: admin@projectred.local / #{password}"
  puts "Client: client@projectred.local / #{password}"
  puts "Staff: producer@projectred.local / #{password}"
end

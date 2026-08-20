require "securerandom"
require "set"

module Aryeo
  class Importer
    ENDPOINTS = {
      staff: "company-team-members",
      clients: "customers",
      customer_teams: "customer-teams",
      products: "products",
      listings: "listings",
      orders: "orders",
      appointments: "appointments",
      tasks: "tasks"
    }.freeze
    RESOURCE_KEYS = ENDPOINTS.keys.map(&:to_s).freeze

    def initialize(run:, client: nil, resources: nil, listing_start_date: nil, conflict_resolution: nil, listing_limit: nil, skip_resources: [])
      @run = run
      @connection = run.integration_connection
      @organization = run.organization
      @client = client || Client.new(api_key: @connection.api_key)
      @listing_limit = listing_limit.to_i.positive? ? listing_limit.to_i : nil
      requested_resources = resources.nil? ? ENDPOINTS.keys.map(&:to_s) : Array(resources).map(&:to_s)
      @resources = requested_resources.intersection(RESOURCE_KEYS).map(&:to_sym).to_set - skip_resources.map(&:to_sym).to_set
      @listing_start_date = listing_start_date.present? ? Date.iso8601(listing_start_date.to_s) : nil
      @conflict_resolution = conflict_resolution.presence || run.conflict_resolution || "skip"
      @counts = Hash.new(0)
      @conflict_counts = Hash.new(0)
      @filtered_counts = Hash.new(0)
      @coverage = {}
      @errors = []
    end

    def call
      @run.update!(status: :running, phase: "starting", started_at: Time.current)
      @connection.update!(status: :importing)

      ENDPOINTS.each do |name, endpoint|
        unless @resources.include?(name)
          @coverage[name] = { status: "skipped", detail: "Not selected for this import run" }
          next
        end

        import_collection(name, endpoint, limit: name == :listings ? @listing_limit : nil)
      end

      finish!
    rescue StandardError => error
      @run.update!(status: :failed, phase: "failed", completed_at: Time.current,
                   counts: @counts, coverage: @coverage, error_details: @errors + [ error.message ])
      @connection.update!(status: :invalid) if error.is_a?(Client::Error)
      raise
    end

    private

    def import_collection(name, endpoint, limit: nil)
      @run.update!(phase: name.to_s)
      count_before = @counts[name]
      if limit
        payloads = []
        @client.paginate(endpoint) { |payload| payloads << stringify(payload) }
        payloads.sort_by { |payload| [ source_timestamp(payload), external_id(payload) ] }.reverse.first(limit).each do |payload|
          import_resource(name, payload)
        end
      else
        @client.paginate(endpoint) do |payload|
          payload = stringify(payload)
          if name == :listings && @listing_start_date && !listing_on_or_after?(payload)
            @filtered_counts[name] += 1
            next
          end
          import_resource(name, payload)
        end
      end
      @coverage[name] = {
        status: "imported",
        count: @counts[name] - count_before,
        skipped_conflicts: @conflict_counts[name],
        filtered_before_date: @filtered_counts[name]
      }.compact
    rescue Client::EndpointUnavailable => error
      @coverage[name] = { status: "unavailable", detail: error.message }
    rescue Client::Error => error
      @coverage[name] = { status: "failed", detail: error.message }
      @errors << "#{name}: #{error.message}"
    ensure
      @run.update!(counts: @counts, coverage: @coverage, error_details: @errors)
    end

    def import_resource(name, payload)
      existing_record = record_for(name.to_s, external_id(payload))
      if existing_record&.record.present? && @conflict_resolution == "skip"
        archive!(name, payload, record: existing_record.record, sync_status: :skipped)
        @conflict_counts[name] += 1
        return
      end

      record = case name
      when :staff then import_staff(payload)
      when :clients then import_client(payload)
      when :customer_teams then import_customer_team(payload)
      when :products then import_product(payload)
      when :listings then import_listing(payload)
      when :orders then import_order(payload)
      when :appointments then import_appointment(payload)
      when :tasks then import_task(payload)
      end

      archive!(name, payload, record: record)
      @counts[name] += 1
    rescue ActiveRecord::RecordInvalid => error
      @errors << "#{name} #{external_id(payload) || "unknown"}: #{error.record.errors.full_messages.to_sentence}"
    end

    def import_staff(payload)
      email = value(payload, "email", "email_address").to_s.downcase
      return if email.blank?

      user = @organization.users.find_by(email: email) || User.find_by(email: email)
      return user if user&.organization_id == @organization.id
      return if user.present?

      password = SecureRandom.urlsafe_base64(32)
      @organization.users.create!(
        name: value(payload, "name", "full_name", "display_name").presence || email.split("@").first,
        email: email,
        role: :production_staff,
        status: :suspended,
        password: password,
        password_confirmation: password,
        origin: :aryeo
      )
    end

    def import_client(payload)
      external = external_id(payload)
      return if external.blank?

      client = record_for("clients", external)&.record || @organization.client_accounts.find_by("metadata ->> 'aryeo_id' = ?", external)
      client ||= @organization.client_accounts.build(metadata: { "aryeo_id" => external })
      client.assign_attributes(
        name: value(payload, "name", "full_name", "company_name").presence || "Aryeo client #{external}",
        email: value(payload, "email", "email_address"),
        phone: value(payload, "phone", "phone_number"),
        brokerage_name: value(payload, "brokerage_name", "company"),
        kind: client_kind(payload),
        origin: :aryeo,
        metadata: client.metadata.merge("aryeo_id" => external)
      )
      client.save!
      client
    end

    def import_customer_team(payload)
      external = external_id(payload)
      return if external.blank?

      team = record_for("customer_teams", external)&.record
      name = value(payload, "name", "brokerage_name").presence || "Aryeo customer team #{external}"
      team ||= @organization.customer_teams.find_by("lower(name) = ?", name.downcase)
      team ||= @organization.customer_teams.build
      team.assign_attributes(
        name: name,
        brokerage_name: value(payload, "brokerage_name"),
        brokerage_website: value(payload, "brokerage_website"),
        website: value(payload, "website"),
        logo_url: value(payload, "logo_url"),
        description: value(payload, "description"),
        archived: boolean_value(payload, "is_archived"),
        origin: :aryeo
      )
      team.save!

      customer_ids(payload).each do |customer_id|
        account = record_for("clients", customer_id)&.record
        team.customer_team_memberships.find_or_create_by!(client_account: account) if account
      end
      team
    end

    def import_product(payload)
      external = external_id(payload)
      return if external.blank?

      product = record_for("products", external)&.record || @organization.products.find_by(external_source: "aryeo", external_id: external)
      attributes = {
        title: value(payload, "title", "name").presence || "Aryeo product #{external}",
        description: value(payload, "description"),
        kind: product_kind(payload),
        active: active?(payload),
        categories: Array(payload["categories"] || payload["category_names"] || payload.dig("category", "name")).compact,
        source_payload: PayloadSanitizer.call(payload),
        origin: :aryeo
      }
      product ||= @organization.products.build(external_source: "aryeo", external_id: external,
                                                slug: unique_product_slug(attributes[:title], external))
      product.assign_attributes(attributes)
      product.save!

      Array(payload["variants"] || payload["product_variants"] || payload["prices"]).each do |variant_payload|
        import_variant(product, stringify(variant_payload))
      end
      product
    end

    def import_variant(product, payload)
      external = external_id(payload)
      return if external.blank?

      variant = product.product_variants.find_or_initialize_by(external_id: external)
      sqft_min, sqft_max = sqft_range(payload)
      variant.assign_attributes(
        title: value(payload, "title", "name").presence || product.title,
        price_cents: cents(payload),
        duration_minutes: value(payload, "duration_minutes", "duration").presence,
        sqft_min: sqft_min,
        sqft_max: sqft_max,
        quantity_label: value(payload, "quantity_label", "quantity", "label"),
        active: active?(payload),
        source_payload: PayloadSanitizer.call(payload)
      )
      variant.save!
    end

    def import_listing(payload)
      external = external_id(payload)
      return if external.blank?

      listing = record_for("listings", external)&.record || @organization.listings.find_by("metadata ->> 'aryeo_id' = ?", external)
      client = client_for(payload) || imported_client
      address = stringify(payload["address"] || payload["property_address"] || {})
      listing ||= @organization.listings.build(client_account: client, metadata: { "aryeo_id" => external })
      listing.assign_attributes(
        client_account: client,
        address_line_1: value(address, "address_line_1", "line1", "street_address", "address").presence || value(payload, "address_line_1", "address").presence || "Aryeo listing #{external}",
        address_line_2: value(address, "address_line_2", "line2", "unit"),
        city: value(address, "city").presence || value(payload, "city"),
        province: value(address, "state", "province", "region").presence || value(payload, "province", "state"),
        postal_code: value(address, "postal_code", "zip", "zip_code").presence || value(payload, "postal_code"),
        country: value(address, "country", "country_code").presence || "CA",
        square_feet: integer_value(payload, "square_feet", "sqft", "square_footage"),
        bedrooms: integer_value(payload, "bedrooms"),
        bathrooms: decimal_value(payload, "bathrooms"),
        mls_number: value(payload, "mls_number", "mls_id"),
        status: listing_status(payload),
        delivery_status: delivery_status(payload),
        scheduled_at: time_value(payload, "scheduled_at", "appointment_at"),
        delivered_at: time_value(payload, "delivered_at"),
        public_slug: value(payload, "public_slug", "slug").presence || "aryeo-#{external}",
        tags: Array(payload["tags"]).filter_map { |tag| tag.is_a?(Hash) ? tag["name"] : tag },
        origin: :aryeo,
        metadata: listing.metadata.merge("aryeo_id" => external, "aryeo_status" => value(payload, "status"))
      )
      listing.save!
      import_listing_media(listing, payload)
      import_property_site(listing, payload)
      listing
    end

    def import_order(payload)
      external = external_id(payload)
      return if external.blank?

      listing = listing_for(payload)
      client = client_for(payload) || listing&.client_account || imported_client
      order = record_for("orders", external)&.record || @organization.orders.find_by("metadata ->> 'aryeo_id' = ?", external)
      order ||= @organization.orders.build(client_account: client, listing: listing, metadata: { "aryeo_id" => external })
      order.assign_attributes(
        client_account: client, listing: listing, source: "aryeo", origin: :aryeo,
        status: order_status(payload), payment_mode: :pay_later, currency: currency(payload),
        subtotal_cents: cents(payload, "subtotal_cents", "subtotal", "sub_total"),
        tax_cents: cents(payload, "tax_cents", "tax"), fee_cents: cents(payload, "fee_cents", "fees"),
        total_cents: cents(payload, "total_cents", "total", "amount"),
        fulfillment_status: fulfillment_status(payload),
        tags: Array(payload["tags"]).filter_map { |tag| tag.is_a?(Hash) ? tag["name"] : tag },
        metadata: order.metadata.merge("aryeo_id" => external, "aryeo_status" => value(payload, "status"))
      )
      order.save!
      Array(payload["items"] || payload["order_items"]).each { |item| import_order_item(order, stringify(item)) }
      import_payment_metadata(order, payload)
      order
    end

    def import_order_item(order, payload)
      external = external_id(payload)
      title = value(payload, "title", "name", "product_name").presence || "Aryeo order item"
      item = external.present? ? order.order_items.find_by("options ->> 'aryeo_id' = ?", external) : nil
      item ||= order.order_items.build(options: external.present? ? { "aryeo_id" => external } : {})
      quantity = integer_value(payload, "quantity") || 1
      item.assign_attributes(title: title, description: value(payload, "description"), quantity: quantity,
                             unit_price_cents: cents(payload, "unit_price_cents", "unit_price", "price"),
                             total_cents: cents(payload, "total_cents", "total", "amount"),
                             snapshot: PayloadSanitizer.call(payload))
      item.save!
    end

    def import_payment_metadata(order, payload)
      payment_payload = PayloadSanitizer.call(stringify(payload["payment"] || payload["payment_info"] || {}))
      return if payment_payload.blank?

      invoice = @organization.invoices.find_or_initialize_by(number: "ARYEO-#{external_id(payload)}")
      total = cents(payload, "total_cents", "total", "amount")
      invoice.assign_attributes(client_account: order.client_account, listing: order.listing, order: order, origin: :aryeo,
                                status: payment_status(payment_payload), currency: currency(payload), subtotal_cents: total,
                                total_cents: total, balance_due_cents: payment_paid?(payment_payload) ? 0 : total,
                                payment_provider: "aryeo", provider_invoice_id: external_id(payment_payload))
      invoice.save!
      payment_id = external_id(payment_payload)
      return if payment_id.blank?

      payment = Payment.find_or_initialize_by(provider: "aryeo", provider_payment_id: payment_id)
      payment.assign_attributes(invoice: invoice, organization: @organization, status: payment_paid?(payment_payload) ? :succeeded : :pending,
                                amount_cents: cents(payment_payload, "amount_cents", "amount", "total") || total,
                                currency: currency(payment_payload), paid_at: time_value(payment_payload, "paid_at", "completed_at"),
                                provider_payload: payment_payload, origin: :aryeo)
      payment.save!
    end

    def import_appointment(payload)
      external = external_id(payload)
      listing = listing_for(payload)
      return if external.blank? || listing.blank?

      appointment = record_for("appointments", external)&.record || @organization.appointments.find_by("notes LIKE ?", "%[aryeo:#{external}]%")
      starts_at = time_value(payload, "starts_at", "start_at", "scheduled_at", "start_time")
      return if starts_at.blank?

      appointment ||= @organization.appointments.build(listing: listing)
      appointment.assign_attributes(listing: listing, order: order_for(payload), assigned_user: staff_for(payload),
                                    status: appointment_status(payload), starts_at: starts_at,
                                    ends_at: time_value(payload, "ends_at", "end_at", "end_time") || starts_at + 1.hour,
                                    notes: [ value(payload, "notes", "description"), "[aryeo:#{external}]" ].compact.join("\n"),
                                    origin: :aryeo)
      appointment.save!
      appointment
    end

    def import_task(payload)
      external = external_id(payload)
      listing = listing_for(payload)
      return if external.blank? || listing.blank?

      task = record_for("tasks", external)&.record || @organization.workflow_tasks.find_by("metadata ->> 'aryeo_id' = ?", external)
      task ||= @organization.workflow_tasks.build(listing: listing, metadata: { "aryeo_id" => external })
      task.assign_attributes(listing: listing, title: value(payload, "title", "name").presence || "Aryeo task #{external}",
                             description: value(payload, "description", "notes"), assignee: staff_for(payload),
                             status: workflow_status(payload), stage: value(payload, "stage", "category").presence || "imported",
                             priority: task_priority(payload), customer_visible: false,
                             due_at: time_value(payload, "due_at", "due_date"), completed_at: time_value(payload, "completed_at"),
                             origin: :aryeo, metadata: task.metadata.merge("aryeo_id" => external))
      task.save!
      task
    end

    def import_listing_media(listing, payload)
      { "images" => "images", "videos" => "videos", "floor_plans" => "floor_plans", "files" => "files", "media" => "files" }.each do |key, category|
        Array(payload[key]).each { |media| import_media_asset(listing, stringify(media), category) }
      end
    end

    def import_media_asset(listing, payload, category)
      external = external_id(payload)
      return if external.blank?

      source_url = value(payload, "url", "download_url", "original_url", "file_url")
      asset = record_for("media_assets", external)&.record
      asset ||= @organization.media_assets.build(listing: listing, metadata: { "aryeo_id" => external })
      asset.assign_attributes(listing: listing, filename: value(payload, "filename", "name", "title").presence || "Aryeo media #{external}",
                              content_type: value(payload, "content_type", "mime_type").presence || content_type_for(category),
                              byte_size: integer_value(payload, "byte_size", "filesize", "size"), width: integer_value(payload, "width"),
                              height: integer_value(payload, "height"), duration_seconds: integer_value(payload, "duration_seconds", "duration"),
                              category: MediaAsset::CATEGORIES.include?(category) ? category : "files", status: :pending,
                              storage_key: DeliveryStorage.key_for(organization: @organization, listing: listing, filename: value(payload, "filename", "name", "title")),
                              source_url: nil, customer_visible: true, origin: :aryeo,
                              metadata: asset.metadata.merge("aryeo_id" => external, "aryeo_source_url" => source_url))
      asset.save!
      external_record = archive!("media_assets", payload, record: asset,
                                 metadata: { "media_url" => source_url }, sync_status: source_url.present? ? :pending_media_copy : :imported)
      AryeoMediaCopyJob.perform_later(external_record.id) if source_url.present? && !asset.ready?
      asset
    end

    def import_property_site(listing, payload)
      site_payload = stringify(payload["property_website"] || payload["property_site"] || {})
      return if site_payload.blank?

      external = external_id(site_payload) || "listing-#{external_id(payload)}"
      site = record_for("property_sites", external)&.record || listing.property_site || @organization.property_sites.build(listing: listing)
      site.assign_attributes(listing: listing, slug: value(site_payload, "slug").presence || "aryeo-#{external}",
                             custom_domain: value(site_payload, "domain", "custom_domain"), status: site_status(site_payload),
                             customer_visible: true, origin: :aryeo,
                             settings: PayloadSanitizer.call(site_payload))
      site.save!
      archive!("property_sites", site_payload, record: site)
    end

    def archive!(resource_type, payload, record: nil, metadata: {}, sync_status: :imported)
      external = external_id(payload)
      return if external.blank?

      external_record = @connection.external_records.find_or_initialize_by(resource_type: resource_type.to_s, external_id: external)
      external_record.assign_attributes(organization: @organization, integration_import_run: @run, provider: :aryeo, record: record,
                                        source_payload: PayloadSanitizer.call(payload), metadata: metadata,
                                        sync_status: sync_status, source_created_at: time_value(payload, "created_at"),
                                        source_updated_at: time_value(payload, "updated_at"), last_imported_at: Time.current)
      external_record.save!
      external_record
    end

    def finish!
      status = @errors.empty? ? :completed : :completed_with_errors
      @run.update!(status:, phase: "completed", completed_at: Time.current, counts: @counts, coverage: @coverage, error_details: @errors)
      @connection.update!(status: :connected, last_imported_at: Time.current, endpoint_coverage: @coverage)
    end

    def listing_on_or_after?(payload)
      raw_timestamp = value(payload, "updated_at", "created_at")
      return false if raw_timestamp.blank?

      Date.parse(raw_timestamp.to_s) >= @listing_start_date
    rescue Date::Error
      false
    end

    def record_for(resource_type, external)
      @connection.external_records.find_by(resource_type: resource_type, external_id: external)
    end

    def client_for(payload)
      nested = stringify(payload["customer"] || payload["client"] || {})
      external = external_id(nested).presence || value(payload, "customer_id", "client_id")
      return record_for("clients", external)&.record if external.present?

      email = value(nested, "email", "email_address").presence || value(payload, "customer_email", "client_email")
      @organization.client_accounts.find_by(email: email) if email.present?
    end

    def imported_client
      @organization.client_accounts.find_or_create_by!(email: "aryeo-import@#{@organization.slug}.invalid") do |client|
        client.name = "Imported Aryeo clients"
        client.kind = :agent
        client.origin = :aryeo
      end
    end

    def listing_for(payload)
      nested = stringify(payload["listing"] || {})
      external = external_id(nested).presence || value(payload, "listing_id")
      record_for("listings", external)&.record if external.present?
    end

    def order_for(payload)
      nested = stringify(payload["order"] || {})
      external = external_id(nested).presence || value(payload, "order_id")
      record_for("orders", external)&.record if external.present?
    end

    def staff_for(payload)
      nested = stringify(payload["assigned_user"] || payload["user"] || payload["assignee"] || {})
      external = external_id(nested).presence || value(payload, "assigned_user_id", "user_id", "assignee_id")
      user = record_for("staff", external)&.record if external.present?
      return user if user.is_a?(User)

      email = value(nested, "email", "email_address")
      @organization.users.find_by(email: email) if email.present?
    end

    def product_kind(payload)
      values = [ value(payload, "title", "name"), *Array(payload["categories"]), value(payload.dig("category") || {}, "name") ].compact.join(" ").downcase
      return "package" if values.match?(/package|budget friendly/)
      return "addon" if values.match?(/add[ -]?on/)

      "service"
    end

    def client_kind(payload)
      value(payload, "type", "kind").to_s.match?(/team|brokerage/i) ? :team : :agent
    end

    def listing_status(payload)
      value = value(payload, "status").to_s.downcase
      return value if Listing.statuses.key?(value)
      return :delivered if value.match?(/deliver|complete/)
      return :booked if value.match?(/book|schedule/)

      :draft
    end

    def delivery_status(payload)
      value(payload, "delivery_status", "status").to_s.match?(/deliver|complete/i) ? :delivered : :undelivered
    end

    def order_status(payload)
      value = value(payload, "status").to_s.downcase
      return value if Order.statuses.key?(value)
      return :paid if value.match?(/paid/)
      return :cancelled if value.match?(/cancel/)
      return :invoiced if value.match?(/invoice/)

      :submitted
    end

    def fulfillment_status(payload)
      value(payload, "fulfillment_status", "status").to_s.match?(/fulfill|deliver|complete/i) ? :fulfilled : :unfulfilled
    end

    def appointment_status(payload)
      value = value(payload, "status").to_s.downcase
      return value if Appointment.statuses.key?(value)
      return :completed if value.match?(/complete/)
      return :cancelled if value.match?(/cancel/)
      return :confirmed if value.match?(/confirm/)

      :scheduled
    end

    def workflow_status(payload)
      desired = value(payload, "status").to_s.parameterize(separator: "_")
      return desired if @organization.workflow_columns.exists?(key: desired)

      @organization.workflow_columns.ordered.first&.key || "todo"
    end

    def task_priority(payload)
      value = value(payload, "priority").to_s.downcase
      WorkflowTask.priorities.key?(value) ? value : :normal
    end

    def site_status(payload)
      value = value(payload, "status").to_s.downcase
      PropertySite.statuses.key?(value) ? value : :draft
    end

    def payment_status(payload)
      payment_paid?(payload) ? :paid : :sent
    end

    def payment_paid?(payload)
      value(payload, "status").to_s.match?(/paid|succeed|complete/i)
    end

    def currency(payload)
      value(payload, "currency").presence&.downcase || "cad"
    end

    def active?(payload)
      value = payload["active"]
      value.nil? || value == true || value.to_s != "false"
    end

    def boolean_value(payload, *keys)
      raw_value = value(payload, *keys)
      return false if raw_value.nil?

      ActiveModel::Type::Boolean.new.cast(raw_value)
    end

    def customer_ids(payload)
      values = payload["customer_ids"] || payload["client_ids"] || payload["customers"] || payload["clients"] || []
      Array(values).filter_map do |item|
        item.is_a?(Hash) ? external_id(stringify(item)) : item.to_s.presence
      end
    end

    def content_type_for(category)
      category == "images" ? "image/*" : category == "videos" ? "video/*" : "application/octet-stream"
    end

    def unique_product_slug(title, external)
      base = "aryeo-#{title.to_s.parameterize.presence || "product"}-#{external}".truncate(90, omission: "")
      base
    end

    def sqft_range(payload)
      min = integer_value(payload, "sqft_min", "square_feet_min", "minimum_square_feet")
      max = integer_value(payload, "sqft_max", "square_feet_max", "maximum_square_feet")
      label = value(payload, "title", "name", "label", "quantity_label").to_s
      match = label.match(/(\d[\d,]*)\s*(?:-|to)\s*(\d[\d,]*)\s*(?:sq\.?\s*ft|sqft)?/i)
      [ min || match&.captures&.first&.delete(",")&.to_i, max || match&.captures&.second&.delete(",")&.to_i ]
    end

    def cents(payload, *keys)
      keys = %w[price_cents price amount] if keys.empty?
      value = keys.lazy.map { |key| payload[key] }.find(&:present?)
      return 0 if value.blank?
      return value.to_i if keys.any? { |key| key.end_with?("_cents") && payload[key].present? }

      (value.to_s.gsub(/[^0-9.\-]/, "").to_d * 100).round
    end

    def integer_value(payload, *keys)
      value = keys.lazy.map { |key| payload[key] }.find(&:present?)
      value.to_s.gsub(/[^0-9\-]/, "").to_i if value.present?
    end

    def decimal_value(payload, *keys)
      value = keys.lazy.map { |key| payload[key] }.find(&:present?)
      value.to_d if value.present?
    end

    def time_value(payload, *keys)
      value = keys.lazy.map { |key| payload[key] }.find(&:present?)
      Time.zone.parse(value.to_s) if value.present?
    rescue ArgumentError
      nil
    end

    def source_timestamp(payload)
      time_value(payload, "updated_at", "created_at", "scheduled_at") || Time.at(0)
    end

    def external_id(payload)
      value(payload, "id", "uuid", "external_id")&.to_s
    end

    def value(payload, *keys)
      keys.lazy.map { |key| payload[key.to_s] || payload[key.to_sym] }.find(&:present?)
    end

    def stringify(value)
      value.is_a?(Hash) ? value.deep_stringify_keys : {}
    end
  end
end

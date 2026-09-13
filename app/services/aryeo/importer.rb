require "securerandom"
require "set"
require "uri"

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
    DATE_FILTERED_RESOURCES = %i[listings orders appointments].freeze
    ORDER_INCLUDE = %w[
      items
      listing
      customer
      appointments
      appointments.users
      unconfirmed_appointments
    ].join(",").freeze
    LISTING_INCLUDE = %w[
      list_agent
      co_list_agent
      images
      files
      videos
      floor_plans
      interactive_content
      property_website
      orders.appointments
    ].join(",").freeze
    LISTING_MEDIA = {
      "images" => "images",
      "videos" => "videos",
      "floor_plans" => "floor_plans",
      "interactive_content" => "tours",
      "files" => "files",
      "media" => "files"
    }.freeze
    MEDIA_SOURCE_KEYS = {
      "images" => %w[original_url large_url url download_url file_url],
      "videos" => %w[download_url url original_url file_url],
      "floor_plans" => %w[original_url large_url url download_url file_url],
      "tours" => %w[url share_url],
      "files" => %w[url download_url original_url file_url]
    }.freeze
    MEDIA_CONTENT_TYPES = {
      "jpg" => "image/jpeg",
      "jpeg" => "image/jpeg",
      "png" => "image/png",
      "webp" => "image/webp",
      "gif" => "image/gif",
      "heic" => "image/heic",
      "mp4" => "video/mp4",
      "mov" => "video/quicktime",
      "webm" => "video/webm",
      "pdf" => "application/pdf",
      "zip" => "application/zip"
    }.freeze
    HEARTBEAT_EVERY = 25

    def initialize(run:, client: nil, resources: nil, import_start_date: nil, import_end_date: nil, conflict_resolution: nil, listing_limit: nil, skip_resources: [])
      @run = run
      @connection = run.integration_connection
      @organization = run.organization
      @client = client || Client.new(api_key: @connection.api_key)
      @listing_limit = listing_limit.to_i.positive? ? listing_limit.to_i : nil
      requested_resources = resources.nil? ? ENDPOINTS.keys.map(&:to_s) : Array(resources).map(&:to_s)
      @resources = requested_resources.intersection(RESOURCE_KEYS).map(&:to_sym).to_set - skip_resources.map(&:to_sym).to_set
      @import_start_date = import_start_date.present? ? Date.iso8601(import_start_date.to_s) : nil
      @import_end_date = import_end_date.present? ? Date.iso8601(import_end_date.to_s) : nil
      @conflict_resolution = conflict_resolution.presence || run.conflict_resolution || "skip"
      @counts = Hash.new(0)
      @conflict_counts = Hash.new(0)
      @filtered_counts = Hash.new(0)
      @filtered_after_counts = Hash.new(0)
      @date_unavailable_counts = Hash.new(0)
      @dependency_counts = Hash.new(0)
      @dependency_conflict_counts = Hash.new(0)
      @media_counts = Hash.new(0)
      @deferred_skipped_resources = []
      @coverage = {}
      @errors = []
      @records_since_heartbeat = 0
    end

    def call
      @run.update!(status: :running, phase: "starting", started_at: Time.current, heartbeat_at: Time.current)
      @connection.update!(status: :importing)

      ENDPOINTS.each do |name, endpoint|
        unless @resources.include?(name)
          @deferred_skipped_resources << name
          next
        end

        import_collection(name, endpoint, limit: name == :listings ? @listing_limit : nil)
      end

      heartbeat!(force: true)
      reconcile_imported_delivery_graph!
      heartbeat!(force: true)
      finish!
    rescue StandardError => error
      @run.mark_failed!(error.message, counts: @counts, coverage: @coverage, error_details: @errors)
      @connection.update!(status: :invalid) if error.is_a?(Client::Error)
      raise
    end

    private

    def heartbeat!(force: false)
      if force
        @run.heartbeat!
        @records_since_heartbeat = 0
        return
      end

      @records_since_heartbeat += 1
      return if @records_since_heartbeat < HEARTBEAT_EVERY

      @run.heartbeat!
      @records_since_heartbeat = 0
    end

    def import_collection(name, endpoint, limit: nil)
      @run.update!(phase: name.to_s)
      heartbeat!(force: true)
      count_before = @counts[name]
      if limit
        payloads = []
        paginate_collection(name, endpoint) do |payload|
          payloads << stringify(payload)
          heartbeat!
        end
        payloads = payloads.filter_map do |payload|
          filter_reason = date_filter_reason(name, payload)
          if filter_reason == :unavailable
            @date_unavailable_counts[name] += 1
            payload
          elsif filter_reason
            increment_filtered_count(name, filter_reason)
            nil
          else
            payload
          end
        end
        payloads.sort_by { |payload| [ source_timestamp(payload), external_id(payload) ] }.reverse.first(limit).each do |payload|
          import_resource(name, payload)
          heartbeat!
        end
      else
        paginate_collection(name, endpoint) do |payload|
          payload = stringify(payload)
          filter_reason = date_filter_reason(name, payload)
          if filter_reason == :unavailable
            @date_unavailable_counts[name] += 1
          elsif filter_reason
            increment_filtered_count(name, filter_reason)
            heartbeat!
            next
          end
          import_resource(name, payload)
          heartbeat!
        end
      end
      @coverage[name] = {
        status: "imported",
        count: @counts[name] - count_before,
        skipped_conflicts: @conflict_counts[name],
        filtered_before_date: @filtered_counts[name],
        filtered_after_date: @filtered_after_counts[name],
        date_unavailable: @date_unavailable_counts[name],
        media_assets: name == :listings && @media_counts.present? ? @media_counts.dup : nil
      }.compact
    rescue Client::EndpointUnavailable => error
      @coverage[name] = { status: "unavailable", detail: error.message }
      Rails.logger.warn("Aryeo import #{@run.id} endpoint unavailable: #{name}: #{error.message}")
    rescue Client::Error => error
      @coverage[name] = { status: "failed", detail: error.message }
      @errors << "#{name}: #{error.message}"
      Rails.logger.warn("Aryeo import #{@run.id} endpoint failed: #{name}: #{error.message}")
    ensure
      @run.update!(counts: @counts, coverage: @coverage, error_details: @errors, heartbeat_at: Time.current)
    end

    def import_resource(name, payload, dependency: false)
      existing_record = record_for(name.to_s, external_id(payload))
      if existing_record&.record.present? && @conflict_resolution == "skip"
        archive!(name, payload, record: existing_record.record, sync_status: :skipped)
        dependency ? @dependency_conflict_counts[name] += 1 : @conflict_counts[name] += 1
        return existing_record.record
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
      @dependency_counts[name] += 1 if dependency
      record
    rescue ActiveRecord::RecordInvalid => error
      message = "#{name} #{external_id(payload) || "unknown"}: #{error.record.errors.full_messages.to_sentence}"
      @errors << message
      Rails.logger.warn("Aryeo import #{@run.id} record skipped: #{message}")
    end

    def import_staff(payload)
      email = value(payload, "email", "email_address").to_s.downcase
      return if email.blank?

      user = @organization.users.find_by(email: email) || User.find_by(email: email)
      return user if user&.organization_id == @organization.id
      return if user.present?

      password = SecureRandom.urlsafe_base64(32)
      @organization.users.create!(
        name: person_name(payload).presence || email.split("@").first,
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
        name: person_name(payload, "company_name").presence || "Aryeo client #{external}",
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

      customer_payloads(payload).each do |customer_payload|
        customer_id = external_id(customer_payload)
        account = record_for("clients", customer_id)&.record
        if customer_id.present? && account.blank? && customer_payload_has_profile?(customer_payload)
          account = import_resource(:clients, customer_payload, dependency: true)
        end
        team.customer_team_memberships.find_or_create_by!(client_account: account) if account
      end
      team
    end

    # Only the fields the CRM acts on get their own column; the rest of the Aryeo
    # payload is kept verbatim in `source_payload` (sanitized), on both the
    # product and each variant. Nothing is dropped, so a field can be promoted to
    # a real column later by backfilling from `source_payload` -- no re-import.
    #
    # Retained but unmapped today, as of the live Aryeo catalog:
    #   product: tags, is_twilight, always_display_addons, type
    #   variant: base_price_amount, base_is_hidden, display_original_price
    # `price_amount` and `base_price_amount` duplicate `price`; all three are
    # cents. See `cents` below for why that matters.
    def import_product(payload)
      external = external_id(payload)
      return if external.blank?

      product = record_for("products", external)&.record || @organization.products.find_by(external_source: "aryeo", external_id: external)
      attributes = {
        title: value(payload, "title", "name").presence || "Aryeo product #{external}",
        description: value(payload, "description"),
        kind: product_kind(payload),
        deliverable_type: product_deliverable_type(payload),
        sla_days: integer_value(payload, "sla_days", "turnaround_days", "delivery_days") || 0,
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
        price_cents: cents(payload, "price_cents", "price_amount", "unit_price_amount", "base_price_amount", "price", "amount"),
        duration_minutes: integer_value(payload, "duration_minutes", "duration"),
        sqft_min: sqft_min,
        sqft_max: sqft_max,
        quantity_label: value(payload, "quantity_label", "quantity_label_text", "label", "subtitle", "sub_title"),
        active: active?(payload),
        source_payload: PayloadSanitizer.call(payload)
      )
      variant.save!
    end

    def import_listing(payload)
      external = external_id(payload)
      return if external.blank?

      listing = record_for("listings", external)&.record || @organization.listings.find_by("metadata ->> 'aryeo_id' = ?", external)
      related_clients = import_listing_clients(payload)
      client = related_clients.first || client_for(payload) || imported_client
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
      related_clients.drop(1).each do |related_client|
        listing.listing_customers.find_or_create_by!(client_account: related_client)
      end
      import_listing_media(listing, payload)
      import_listing_relations(listing, payload)
      import_property_site(listing, payload)
      listing
    end

    def import_listing_clients(payload)
      listing_client_payloads(payload).filter_map do |client_payload|
        client = client_for_payload(client_payload)
        if client.blank? && external_id(client_payload).present?
          client = import_resource(:clients, client_payload, dependency: true)
        end
        import_related_customer_team(client_payload, client)
        client
      end.uniq(&:id)
    end

    def import_listing_relations(listing, payload)
      listing_external = external_id(payload)

      unless @resources.include?(:orders)
        records(payload, "orders").each do |order_payload|
          import_resource(:orders, order_payload.merge("listing_id" => listing_external), dependency: true)
        end
      end

      return if @resources.include?(:appointments)

      records(payload, "appointments", "appointment").each do |appointment_payload|
        import_resource(:appointments, appointment_payload.merge("listing_id" => listing_external), dependency: true)
      end
    end

    def import_related_customer_team(client_payload, client)
      return if client.blank?

      team_payload = records(client_payload, "customer_team", "team").first
      team_external = value(client_payload, "customer_team_id", "team_id")
      team_payload ||= { "id" => team_external } if team_external.present?
      return if team_payload.blank? || external_id(team_payload).blank?

      team_payload = team_payload.merge("customer_ids" => (customer_ids(team_payload) + [ external_id(client_payload) ]).compact.uniq)
      team = record_for("customer_teams", external_id(team_payload))&.record
      team ||= import_resource(:customer_teams, team_payload, dependency: true)
      team&.customer_team_memberships&.find_or_create_by!(client_account: client)
    end

    def import_order(payload)
      external = external_id(payload)
      return if external.blank?

      listing = listing_for(payload)
      listing ||= import_resource(:listings, stringify(payload["listing"]), dependency: true) if listing.blank? && payload["listing"].is_a?(Hash)
      client = client_for(payload)
      client ||= import_order_client(payload)
      client ||= listing&.client_account || imported_client
      order = record_for("orders", external)&.record || @organization.orders.find_by("metadata ->> 'aryeo_id' = ?", external)
      order ||= @organization.orders.build(client_account: client, listing: listing, metadata: { "aryeo_id" => external })
      order.assign_attributes(
        client_account: client, listing: listing, source: "aryeo", origin: :aryeo,
        status: order_status(payload), payment_mode: :pay_later, currency: currency(payload),
        subtotal_cents: cents(payload, "subtotal_cents", "subtotal_amount", "subtotal", "sub_total"),
        tax_cents: cents(payload, "tax_cents", "tax_amount", "tax"), fee_cents: cents(payload, "fee_cents", "fee_amount", "fees"),
        total_cents: cents(payload, "total_cents", "total_amount", "total", "amount"),
        fulfillment_status: fulfillment_status(payload),
        tags: Array(payload["tags"]).filter_map { |tag| tag.is_a?(Hash) ? tag["name"] : tag },
        metadata: order.metadata.merge("aryeo_id" => external, "aryeo_status" => value(payload, "status"))
      )
      order.save!
      records(payload, "items", "order_items", "product_items").each { |item| import_order_item(order, item) }
      import_payment_metadata(order, payload)
      import_order_appointments(order, payload) unless @resources.include?(:appointments)
      order
    end

    def import_order_appointments(order, payload)
      listing_external = order.listing&.metadata&.[]("aryeo_id")
      return if listing_external.blank?

      records(payload, "appointments", "appointment").each do |appointment_payload|
        import_resource(:appointments, appointment_payload.merge("listing_id" => listing_external,
                                                                  "order_id" => external_id(payload)), dependency: true)
      end
    end

    def import_order_item(order, payload)
      external = external_id(payload)
      item = external.present? ? order.order_items.find_by("options ->> 'aryeo_id' = ?", external) : nil
      item ||= order.order_items.build(options: external.present? ? { "aryeo_id" => external } : {})
      quantity = integer_value(payload, "quantity") || 1
      product, variant = order_item_catalog_reference(payload)
      title = value(payload, "title", "name", "product_name").presence || product&.title || "Aryeo order item"
      unit_price_cents = cents(payload, "unit_price_cents", "unit_price_amount", "unit_price", "price_amount", "price")
      total_cents = cents(payload, "total_cents", "total_amount", "gross_total_amount", "total", "amount")
      unit_price_cents = variant.price_cents if !money_value_present?(payload, "unit_price_cents", "unit_price_amount", "unit_price", "price_amount", "price") && variant.present?
      total_cents = unit_price_cents * quantity if !money_value_present?(payload, "total_cents", "total_amount", "gross_total_amount", "total", "amount")
      snapshot = PayloadSanitizer.call(payload)
      snapshot = OrderItem.catalog_snapshot(variant, price_cents: unit_price_cents).merge("aryeo_order_item" => snapshot) if variant.present?
      item.assign_attributes(title: title, description: value(payload, "description", "subtitle", "sub_title"), quantity: quantity,
                             product:, product_variant: variant,
                             unit_price_cents:, total_cents:, cancelled_at: imported_cancelled_at(payload), snapshot:)
      item.save!
    end

    def import_order_client(payload)
      client_payload = listing_client_payloads(payload).first
      return if client_payload.blank? || external_id(client_payload).blank?

      import_resource(:clients, client_payload, dependency: true)
    end

    def order_item_catalog_reference(payload)
      variant_payload = stringify(payload["product_variant"] || payload["variant"] || {})
      product_payload = order_item_product_payload(payload, variant_payload)
      product = resolve_order_item_product(product_payload)
      product ||= imported_product_by_title(payload)
      variant_external = external_id(variant_payload).presence || value(payload, "product_variant_id", "variant_id")&.to_s
      variant = product&.product_variants&.find_by(external_id: variant_external) if variant_external.present?
      variant ||= @organization.product_variants.joins(:product)
                                     .where(products: { organization_id: @organization.id })
                                     .find_by(external_id: variant_external) if variant_external.present?
      variant ||= product&.product_variants&.find_by(title: value(variant_payload, "title", "name")) if variant_payload.present?

      [ product || variant&.product, variant ]
    end

    def imported_product_by_title(payload)
      title = value(payload, "title", "name", "product_name").to_s.strip
      return if title.blank?

      @organization.products.where(origin: :aryeo).find_by("lower(title) = ?", title.downcase)
    end

    def order_item_product_payload(payload, variant_payload)
      nested = %w[product service_product].filter_map do |key|
        candidate = payload[key]
        stringify(candidate) if candidate.is_a?(Hash)
      end.find { |candidate| external_id(candidate).present? }
      return nested if nested.present?

      variant_product = stringify(variant_payload["product"] || variant_payload["service_product"] || {})
      return variant_product if external_id(variant_product).present?

      external = value(payload, "product_id", "service_product_id")
      external.present? ? { "id" => external.to_s } : nil
    end

    def resolve_order_item_product(payload)
      return if payload.blank?

      external = external_id(payload)
      return if external.blank?

      product = record_for("products", external)&.record || @organization.products.find_by(external_source: "aryeo", external_id: external)
      return product if product.present?
      return if payload.keys == [ "id" ]

      import_resource(:products, payload, dependency: true)
    end

    def import_payment_metadata(order, payload)
      payment_payload = PayloadSanitizer.call(stringify(payload["payment"] || payload["payment_info"] || {}))
      return if payment_payload.blank?

      invoice = @organization.invoices.find_or_initialize_by(number: "ARYEO-#{external_id(payload)}")
      total = cents(payload, "total_cents", "total_amount", "total", "amount")
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
      starts_at = time_value(payload, "starts_at", "start_at", "scheduled_at", "start_time", "created_at", "updated_at")
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
                             status: workflow_status(payload),
                             priority: task_priority(payload), customer_visible: false,
                             due_at: time_value(payload, "due_at", "due_date"), completed_at: time_value(payload, "completed_at"),
                             origin: :aryeo, metadata: task.metadata.merge("aryeo_id" => external))
      task.save!
      task
    end

    def import_listing_media(listing, payload)
      LISTING_MEDIA.each do |key, category|
        records(payload, key).each do |media|
          import_media_asset(listing, media, category)
        rescue ActiveRecord::RecordInvalid => error
          @media_counts["failed"] += 1
          @errors << "media_assets #{external_id(media) || "unknown"}: #{error.record.errors.full_messages.to_sentence}"
        end
      end
    end

    def import_media_asset(listing, payload, category)
      external = external_id(payload)
      return if external.blank?

      source_url = value(payload, *MEDIA_SOURCE_KEYS.fetch(category, MEDIA_SOURCE_KEYS["files"])).to_s.presence
      asset = record_for("media_assets", external)&.record
      asset ||= @organization.media_assets.build(listing: listing, metadata: { "aryeo_id" => external })
      filename = media_filename(payload, external, source_url)
      metadata = asset.metadata.merge("aryeo_id" => external)
      if source_url.present?
        metadata["aryeo_source_url"] = source_url
        metadata.delete("processing_error")
      else
        metadata["processing_error"] = "missing_media_url"
        @errors << "media_assets #{external}: Aryeo #{category} record has no downloadable URL"
      end
      content_type = content_type_for(category, payload, source_url)
      asset.assign_attributes(listing: listing, filename:,
                              content_type:,
                              byte_size: integer_value(payload, "byte_size", "filesize", "size"), width: integer_value(payload, "width"),
                              height: integer_value(payload, "height"), duration_seconds: integer_value(payload, "duration_seconds", "duration"),
                              category: media_category_for(category, content_type),
                              position: integer_value(payload, "index", "order_index", "position") || 0,
                              status: source_url.present? ? :pending : :failed,
                              storage_key: asset.storage_key.presence || DeliveryStorage.key_for(organization: @organization, listing: listing, filename:),
                              source_url: nil, customer_visible: true, origin: :aryeo, metadata:)
      asset.save!
      @media_counts[source_url.present? ? "queued" : "failed"] += 1
      external_record = archive!("media_assets", payload, record: asset,
                                 metadata: { "media_url" => source_url }, sync_status: source_url.present? ? :pending_media_copy : :failed)
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
      @deferred_skipped_resources.each do |name|
        @coverage[name] ||= { status: "skipped", detail: "Not selected for this import run" }
      end
      @dependency_counts.keys.union(@dependency_conflict_counts.keys).each do |name|
        count = @dependency_counts[name]
        skipped_conflicts = @dependency_conflict_counts[name]
        next if count.zero? && skipped_conflicts.zero?

        @coverage[name] = {
          status: "imported_as_dependency",
          count: count,
          skipped_conflicts: skipped_conflicts
        }.compact
      end
      status = @errors.empty? ? :completed : :completed_with_errors
      Rails.logger.warn("Aryeo import #{@run.id} completed with errors: #{@errors.join("; ")}") if @errors.present?
      @run.update!(status:, phase: "completed", completed_at: Time.current, heartbeat_at: Time.current,
                   counts: @counts, coverage: @coverage, error_details: @errors)
      @connection.update!(status: :connected, last_imported_at: Time.current, endpoint_coverage: @coverage)
    end

    def reconcile_imported_delivery_graph!
      # Listings and media are imported before the complete order/catalog graph
      # is known. Reconcile only after all endpoints have been processed, so
      # media is linked to real services by category and provider relationship
      # instead of being left as an orphan listing file.
      result = Aryeo::ImportedDeliveryMaterializer.new(run: @run).call
      linked_count = result.fetch(:linked_media_assets).size
      @media_counts["linked"] += linked_count if linked_count.positive?
      return unless @coverage[:listings].present? && @media_counts.present?

      @coverage[:listings][:media_assets] = @media_counts.dup
    end

    def paginate_collection(name, endpoint, &block)
      params =
        case name
        when :listings then { "include" => LISTING_INCLUDE }
        when :orders then { "include" => ORDER_INCLUDE }
        else {}
        end
      return @client.paginate(endpoint, &block) if params.empty?

      @client.paginate(endpoint, params:, &block)
    end

    def date_filter_reason(name, payload)
      return unless (@import_start_date || @import_end_date) && DATE_FILTERED_RESOURCES.include?(name)

      raw_timestamp = resource_start_timestamp(name, payload)
      return :unavailable if raw_timestamp.blank?

      date = Date.parse(raw_timestamp.to_s)
      return :before if @import_start_date && date < @import_start_date
      return :after if @import_end_date && date > @import_end_date

      nil
    rescue ArgumentError, Date::Error, TypeError
      :unavailable
    end

    def increment_filtered_count(name, reason)
      return unless reason

      reason == :before ? @filtered_counts[name] += 1 : @filtered_after_counts[name] += 1
    end

    def resource_start_timestamp(name, payload)
      case name
      when :listings
        value(payload, "updated_at", "created_at")
      when :appointments
        value(payload, "start_at", "starts_at", "scheduled_at", "start_time", "created_at", "updated_at")
      when :orders
        appointment_timestamps(payload).min || value(payload, "appointment_start_at", "scheduled_at", "created_at", "updated_at")
      end
    end

    def appointment_timestamps(payload)
      records(payload, "appointments", "unconfirmed_appointments", "appointment").filter_map do |appointment|
        value(appointment, "start_at", "starts_at", "scheduled_at", "start_time")
      end
    end

    def record_for(resource_type, external)
      return if external.blank?

      @connection.external_records.find_by(resource_type: resource_type, external_id: external)
    end

    def client_for(payload)
      listing_client_payloads(payload).each do |client_payload|
        client = client_for_payload(client_payload)
        return client if client.present?
      end

      nil
    end

    def client_for_payload(payload)
      external = external_id(payload)
      client = record_for("clients", external)&.record
      client ||= @organization.client_accounts.find_by("metadata ->> 'aryeo_id' = ?", external) if external.present?
      return client if client.present?

      email = value(payload, "email", "email_address")
      @organization.client_accounts.find_by(email: email) if email.present?
    end

    def listing_client_payloads(payload)
      candidates = records(payload, "customer", "client", "customer_account", "owner")
      candidates.concat(records(payload, "customers", "clients"))
      %w[customer_id client_id customer_account_id owner_id].each do |key|
        external = value(payload, key)
        candidates << { "id" => external } if external.present?
      end
      candidates.select { |candidate| external_id(candidate).present? || value(candidate, "email", "email_address").present? }
        .uniq { |candidate| external_id(candidate).presence || value(candidate, "email", "email_address").to_s.downcase }
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
      record_for("listings", external)&.record || @organization.listings.find_by("metadata ->> 'aryeo_id' = ?", external) if external.present?
    end

    def order_for(payload)
      nested = stringify(payload["order"] || {})
      external = external_id(nested).presence || value(payload, "order_id")
      record_for("orders", external)&.record || @organization.orders.find_by("metadata ->> 'aryeo_id' = ?", external) if external.present?
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
      source_kind = value(payload, "kind", "product_kind", "type").to_s.upcase.gsub(/[^A-Z]/, "")
      return "addon" if source_kind == "ADDON"

      # Aryeo exposes MAIN and ADDON products, not ProjectRed packages. A
      # display title, category, or free-form component-looking field cannot
      # create a package relationship; packages are configured in ProjectRed.
      "service"
    end

    def person_name(payload, *fallback_keys)
      full_name = [ value(payload, "first_name"), value(payload, "last_name") ].compact.join(" ").presence
      full_name || value(payload, "name", "full_name", "display_name", *fallback_keys)
    end

    def product_deliverable_type(payload)
      explicit = value(payload, "deliverable_type", "service_type", "deliverable", "service_category")
      candidate = normalize_deliverable_type(explicit)
      return candidate if candidate.present?

      searchable = [ value(payload, "title", "name", "description"), *text_values(payload["categories"]),
                     *text_values(payload["category"]) ].compact.join(" ").downcase
      return "photography" if searchable.match?(/photo|image|photograph/)
      return "vertical_reel" if searchable.match?(/vertical|reel|short.?form/)
      return "video" if searchable.match?(/video|cinema|film/)
      return "drone" if searchable.match?(/drone|aerial/)
      return "floor_plan" if searchable.match?(/floor.?plan|flooring/)
      return "tour" if searchable.match?(/tour|matterport|3d/)
      return "property_site" if searchable.match?(/property.?site|website/)
      return "files" if searchable.match?(/file|document/)

      "other"
    end

    def normalize_deliverable_type(value)
      normalized = value.to_s.downcase.parameterize(separator: "_")
      {
        "photo" => "photography", "photos" => "photography", "photography" => "photography",
        "image" => "photography", "images" => "photography",
        "video" => "video", "videos" => "video", "vertical_reel" => "vertical_reel",
        "drone" => "drone", "aerial" => "drone", "floor_plan" => "floor_plan",
        "tour" => "tour", "property_site" => "property_site", "files" => "files",
        "other" => "other"
      }[normalized]
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

    def imported_cancelled_at(payload)
      return unless boolean_value(payload, "is_canceled", "is_cancelled", "cancelled", "canceled")

      time_value(payload, "cancelled_at", "canceled_at") || Time.current
    end

    def currency(payload)
      value(payload, "currency").presence&.downcase || "cad"
    end

    def active?(payload)
      return boolean_value(payload, "active") if payload.key?("active")

      true
    end

    def boolean_value(payload, *keys)
      raw_value = value(payload, *keys)
      return false if raw_value.nil?

      ActiveModel::Type::Boolean.new.cast(raw_value)
    end

    def customer_ids(payload)
      customer_payloads(payload).filter_map { |customer| external_id(customer) }
    end

    def customer_payload_has_profile?(payload)
      person_name(payload).present? || value(payload, "email", "email_address", "phone", "phone_number").present?
    end

    def records(payload, *keys)
      raw_records(payload, *keys).filter_map { |item| item.is_a?(Hash) ? stringify(item) : nil }
    end

    def customer_payloads(payload)
      raw_records(payload, "customers", "clients", "customer_ids", "client_ids").filter_map do |item|
        item.is_a?(Hash) ? stringify(item) : { "id" => item.to_s }
      end.reject { |customer| external_id(customer).blank? }
    end

    def raw_records(payload, *keys)
      raw = keys.lazy.map do |key|
        next payload[key.to_s] if payload.key?(key.to_s)
        next payload[key.to_sym] if payload.key?(key.to_sym)
      end.find { |value| !value.nil? }
      return [] if raw.nil?

      values = collection_values(raw)
      values.is_a?(Array) ? values : [ values ]
    end

    def collection_values(value)
      return value unless value.is_a?(Hash)

      collection = %w[data results items records listings].filter_map do |key|
        candidate = value[key]
        candidate if candidate.is_a?(Array) || candidate.is_a?(Hash)
      end.first
      collection || value
    end

    def text_values(value)
      case value
      when Hash then value.values.flat_map { |entry| text_values(entry) }
      when Array then value.flat_map { |entry| text_values(entry) }
      else [ value.to_s ]
      end
    end

    def money_value_present?(payload, *keys)
      keys.any? { |key| payload[key.to_s].present? || payload[key.to_sym].present? }
    end

    def content_type_for(category, payload = {}, source_url = nil)
      explicit = value(payload, "content_type", "mime_type").to_s.split(";").first.presence
      return explicit if explicit.present?

      extension = value(payload, "file_type", "extension").to_s.downcase.sub(/\A\./, "")
      extension = File.extname(source_filename(source_url).to_s).delete_prefix(".").downcase if extension.blank?
      return MEDIA_CONTENT_TYPES[extension] if MEDIA_CONTENT_TYPES.key?(extension)

      case category
      when "images", "floor_plans" then "image/jpeg"
      when "videos" then "video/mp4"
      else "application/octet-stream"
      end
    end

    def media_filename(payload, external, source_url)
      filename = value(payload, "filename", "file_name", "name", "title").to_s.strip
      source_name = source_filename(source_url)
      return filename if filename.present? && (File.extname(filename).present? || source_name.blank?)
      return "#{filename}#{File.extname(source_name)}" if filename.present? && File.extname(source_name).present?

      filename.presence || source_name.presence || "Aryeo media #{external}"
    end

    def media_category_for(category, content_type)
      return "images" if category == "files" && content_type.start_with?("image/")
      return "videos" if category == "files" && content_type.start_with?("video/")

      MediaAsset::CATEGORIES.include?(category) ? category : "files"
    end

    def source_filename(source_url)
      return if source_url.blank?

      File.basename(URI.parse(source_url).path.to_s).presence
    rescue URI::InvalidURIError
      nil
    end

    def unique_product_slug(title, external)
      base = "aryeo-#{title.to_s.parameterize.presence || "product"}-#{external}".truncate(90, omission: "")
      base
    end

    def sqft_range(payload)
      min = integer_value(payload, "sqft_min", "square_feet_min", "minimum_square_feet")
      max = integer_value(payload, "sqft_max", "square_feet_max", "maximum_square_feet")
      label = value(payload, "title", "name", "label", "quantity_label", "subtitle", "sub_title").to_s
      match = label.match(/(\d[\d,]*)\s*(?:-|–|—|to)\s*(\d[\d,]*)\s*(?:sq\.?\s*ft|sqft)?/i)
      max ||= label.match(/(?:up\s*to|under)\s*(\d[\d,]*)/i)&.captures&.first&.delete(",")&.to_i
      min ||= label.match(/(\d[\d,]*)\s*\+/)&.captures&.first&.delete(",")&.to_i
      [ min || match&.captures&.first&.delete(",")&.to_i, max || match&.captures&.second&.delete(",")&.to_i ]
    end

    # Aryeo reports every monetary field as an integer number of cents, whatever
    # the key is called: `price`, `total`, and `amount` are cents just as much as
    # `price_cents` is. An earlier version only trusted the `_cents` suffix and
    # multiplied everything else by 100, which stored a $150.00 product variant
    # (`"price" => 15000`) as $15,000.00. Treat a whole number as cents, and only
    # scale a value that actually carries a decimal fraction -- that shape comes
    # from a hand-written fixture or a CSV, never from the Aryeo API.
    def cents(payload, *keys)
      keys = %w[price_cents price_amount unit_price_amount base_price_amount price amount] if keys.empty?
      value = keys.lazy.map { |key| payload[key.to_s] || payload[key.to_sym] }.find(&:present?)
      return 0 if value.blank?

      digits = value.to_s.gsub(/[^0-9.\-]/, "")
      return 0 if digits.match?(/\A-?\.?\z/)

      amount = digits.to_d
      # A whole number is cents, however it was spelled -- `15000` and `15000.0`
      # are the same $150.00. Only a real fraction implies the value was quoted
      # in dollars, because there is no such thing as a fractional cent.
      return amount.to_i if amount.frac.zero?

      (amount * 100).round
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

require "securerandom"

module Aryeo
  # Provider-specific record mapping belongs here. The import organizers decide
  # when this service runs; this service only knows how Aryeo payloads become
  # ProjectRed records and related media.
  class ResourceImporter
    def self.call(session:, name:, payload:)
      new(session:, name:, payload:).call
    end

    def initialize(session:, name:, payload:)
      @session = session
      @name = name.to_sym
      @payload = payload
    end

    def call
      case @name
      when :staff then import_staff
      when :clients then import_client
      when :customer_teams then import_customer_team
      when :products then import_product
      when :listings then import_listing
      when :orders then import_order
      when :appointments then import_appointment
      when :tasks then import_task
      else raise ArgumentError, "Unsupported Aryeo resource: #{@name}"
      end
    end

    private

    attr_reader :session, :payload

    def import_staff
      email = session.value(payload, "email", "email_address").to_s.downcase
      return if email.blank?

      user = session.organization.users.find_by(email:)
      user ||= User.find_by(email:)
      return user if user&.organization_id == session.organization.id
      return if user.present?

      password = SecureRandom.urlsafe_base64(32)
      session.organization.users.create!(
        name: session.person_name(payload).presence || email.split("@").first,
        email:,
        role: :production_staff,
        status: :suspended,
        password:,
        password_confirmation: password,
        origin: :aryeo
      )
    end

    def import_client
      external = session.external_id(payload)
      return if external.blank?

      client = session.record_for("clients", external)&.record ||
               session.organization.client_accounts.find_by("metadata ->> 'aryeo_id' = ?", external)
      client ||= session.organization.client_accounts.build(metadata: { "aryeo_id" => external })
      client.assign_attributes(
        name: session.person_name(payload, "company_name").presence || "Aryeo client #{external}",
        email: session.value(payload, "email", "email_address"),
        phone: session.value(payload, "phone", "phone_number"),
        brokerage_name: session.value(payload, "brokerage_name", "company"),
        kind: session.client_kind(payload),
        origin: :aryeo,
        metadata: client.metadata.merge("aryeo_id" => external)
      )
      client.save!
      client
    end

    # An Aryeo customer team is one of our client accounts: it holds people,
    # and its settings apply to everyone ordering under it. Each person is
    # brought in with an invitation that has not been sent, so nobody hears from
    # us until staff invite them.
    def import_customer_team
      external = session.external_id(payload)
      return if external.blank?

      team = session.record_for("customer_teams", external)&.record
      team = nil unless team.is_a?(ClientAccount)
      team ||= session.organization.client_accounts.find_by("metadata ->> 'aryeo_team_id' = ?", external)
      team ||= session.organization.client_accounts.build(kind: :team)
      team.assign_attributes(
        name: session.value(payload, "name", "brokerage_name").presence || "Aryeo customer team #{external}",
        brokerage_name: session.value(payload, "brokerage_name"),
        brokerage_website: session.value(payload, "brokerage_website"),
        website: session.value(payload, "website"),
        logo_url: session.value(payload, "logo_url"),
        description: session.value(payload, "description"),
        internal_note: session.value(payload, "internal_notes", "internal_note"),
        archived_at: session.boolean_value(payload, "is_archived") ? (team.archived_at || Time.current) : nil,
        origin: :aryeo,
        metadata: team.metadata.merge("aryeo_team_id" => external)
      )
      team.save!

      session.customer_payloads_for(payload).each do |customer_payload|
        customer_id = session.external_id(customer_payload)
        if customer_id.present? && session.record_for("clients", customer_id).blank? && session.customer_payload_has_profile(customer_payload)
          session.import_dependency(:clients, customer_payload)
        end
        session.import_team_member(team, customer_payload)
      end
      session.records(payload, "customer_team_memberships", "memberships").each do |membership_payload|
        person = session.records(membership_payload, "customer_user", "customer", "user").first
        next if person.blank?

        session.import_team_member(team, person, role: session.value(membership_payload, "role"),
                                                 status: session.value(membership_payload, "status"))
      end
      team
    end

    def import_product
      external = session.external_id(payload)
      return if external.blank?

      product = session.record_for("products", external)&.record ||
                session.organization.products.find_by(external_source: "aryeo", external_id: external)
      attributes = {
        title: session.value(payload, "title", "name").presence || "Aryeo product #{external}",
        description: session.value(payload, "description"),
        kind: session.product_kind(payload),
        deliverable_type: session.product_deliverable_type(payload),
        sla_days: session.integer_value(payload, "sla_days", "turnaround_days", "delivery_days") || 0,
        active: session.active?(payload),
        categories: Array(payload["categories"] || payload["category_names"] || payload.dig("category", "name")).compact,
        source_payload: ::Aryeo::PayloadSanitizer.call(payload),
        origin: :aryeo
      }
      product ||= session.organization.products.build(
        external_source: "aryeo",
        external_id: external,
        slug: session.unique_product_slug(attributes[:title], external)
      )
      product.assign_attributes(attributes)
      product.save!
      Array(payload["variants"] || payload["product_variants"] || payload["prices"]).each do |variant_payload|
        import_variant(product, session.stringify(variant_payload))
      end
      product
    end

    def import_variant(product, variant_payload)
      external = session.external_id(variant_payload)
      return if external.blank?

      variant = product.product_variants.find_or_initialize_by(external_id: external)
      sqft_min, sqft_max = session.sqft_range(variant_payload)
      variant.assign_attributes(
        title: session.value(variant_payload, "title", "name").presence || product.title,
        price_cents: session.cents(variant_payload, "price_cents", "price_amount", "unit_price_amount",
                                           "base_price_amount", "price", "amount"),
        duration_minutes: session.integer_value(variant_payload, "duration_minutes", "duration"),
        sqft_min:, sqft_max:,
        quantity_label: session.value(variant_payload, "quantity_label", "quantity_label_text", "label", "subtitle", "sub_title"),
        active: session.active?(variant_payload),
        source_payload: ::Aryeo::PayloadSanitizer.call(variant_payload)
      )
      variant.save!
    end

    def import_listing
      external = session.external_id(payload)
      return if external.blank?

      listing = session.listing_record(external)
      related_clients = session.import_listing_clients(payload)
      client = related_clients.first || session.client_for(payload) || session.imported_client
      team, membership = session.team_and_member_for(payload, client)
      address = session.stringify(payload["address"] || payload["property_address"] || {})
      listing ||= session.organization.listings.build(client_account: team || client, metadata: { "aryeo_id" => external })
      listing.assign_attributes(
        client_account: team || client,
        address_line_1: session.value(address, "address_line_1", "line1", "street_address", "address").presence ||
          session.value(payload, "address_line_1", "address").presence || "Aryeo listing #{external}",
        address_line_2: session.value(address, "address_line_2", "line2", "unit"),
        city: session.value(address, "city").presence || session.value(payload, "city"),
        province: session.value(address, "state", "province", "region").presence || session.value(payload, "province", "state"),
        postal_code: session.value(address, "postal_code", "zip", "zip_code").presence || session.value(payload, "postal_code"),
        country: session.value(address, "country", "country_code").presence || "CA",
        square_feet: session.integer_value(payload, "square_feet", "sqft", "square_footage"),
        bedrooms: session.integer_value(payload, "bedrooms"),
        bathrooms: session.decimal_value(payload, "bathrooms"),
        mls_number: session.value(payload, "mls_number", "mls_id"),
        status: session.listing_status_for(payload),
        delivery_status: session.delivery_status(payload),
        scheduled_at: session.time_value(payload, "scheduled_at", "appointment_at"),
        delivered_at: session.time_value(payload, "delivered_at"),
        public_slug: session.value(payload, "public_slug", "slug").presence || "aryeo-#{external}",
        tags: Array(payload["tags"]).filter_map { |tag| tag.is_a?(Hash) ? tag["name"] : tag },
        origin: :aryeo,
        metadata: listing.metadata.merge("aryeo_id" => external, "aryeo_status" => session.value(payload, "status"))
      )
      listing.booked_by ||= membership&.user
      listing.save!
      related_clients.drop(1).each do |related_client|
        listing.listing_customers.find_or_create_by!(client_account: related_client)
      end
      listing.listing_customers.find_or_create_by!(client_account: client) if team && client.id != team.id
      import_listing_media(listing)
      session.import_listing_relations(listing, payload)
      session.import_property_site(listing, payload)
      listing
    end

    def import_listing_media(listing)
      ::Aryeo::ImportSession::LISTING_MEDIA.each do |key, category|
        session.records(payload, key).each do |media_payload|
          import_media_asset(listing, media_payload, category)
        rescue ActiveRecord::RecordInvalid => error
          session.increment_media!("failed")
          session.record_media_error!(
            "media_assets #{session.external_id(media_payload) || "unknown"}: #{error.message}"
          )
        end
      end
    end

    def import_media_asset(listing, media_payload, category)
      external = session.external_id(media_payload)
      return if external.blank?

      source_url = session.value(
        media_payload,
        *::Aryeo::ImportSession::MEDIA_SOURCE_KEYS.fetch(
          category, ::Aryeo::ImportSession::MEDIA_SOURCE_KEYS["files"]
        )
      ).to_s.presence
      asset = session.record_for("media_assets", external)&.record
      asset ||= session.organization.media_assets.build(listing:, metadata: { "aryeo_id" => external })
      filename = session.media_filename_for(media_payload, external, source_url)
      metadata = asset.metadata.merge("aryeo_id" => external)
      if source_url.present?
        metadata["aryeo_source_url"] = source_url
        metadata.delete("processing_error")
      else
        metadata["processing_error"] = "missing_media_url"
        session.record_media_error!("media_assets #{external}: Aryeo #{category} record has no downloadable URL")
      end
      content_type = session.content_type_for(category, media_payload, source_url)
      asset.assign_attributes(
        listing:,
        filename:,
        content_type:,
        byte_size: session.integer_value(media_payload, "byte_size", "filesize", "size"),
        width: session.integer_value(media_payload, "width"),
        height: session.integer_value(media_payload, "height"),
        duration_seconds: session.integer_value(media_payload, "duration_seconds", "duration"),
        category: session.media_category_for_type(category, content_type),
        position: session.integer_value(media_payload, "index", "order_index", "position") || 0,
        status: source_url.present? ? :pending : :failed,
        storage_key: asset.storage_key.presence || DeliveryStorage.key_for(organization: session.organization, listing:, filename:),
        source_url: nil,
        customer_visible: true,
        origin: :aryeo,
        metadata:
      )
      asset.save!
      session.increment_media!(source_url.present? ? "queued" : "failed")
      external_record = session.archive!(
        "media_assets", media_payload, record: asset, metadata: { "media_url" => source_url },
        sync_status: source_url.present? ? :pending_media_copy : :failed
      )
      ::AryeoMediaCopyJob.perform_later(external_record.id) if source_url.present? && !asset.ready?
    end

    def import_order
      external = session.external_id(payload)
      return if external.blank?

      listing = session.listing_for(payload)
      if listing.blank? && payload["listing"].is_a?(Hash)
        listing = session.import_dependency(:listings, session.stringify(payload["listing"]))
      end
      client = session.client_for(payload)
      client ||= session.import_order_client(payload)
      team, membership = session.team_and_member_for(payload, client)
      session.place_listing_under_team(listing, team, client) if listing
      # The listing decides the team; an order without one follows its customer's team.
      client = listing&.client_account || team || client || session.imported_client
      order = session.order_record(external)
      order ||= session.organization.orders.build(client_account: client, listing:, metadata: { "aryeo_id" => external })
      order.assign_attributes(
        client_account: client,
        listing:,
        ordered_by: order.ordered_by || membership&.user || listing&.booked_by,
        source: "aryeo",
        origin: :aryeo,
        status: session.order_status_for(payload),
        payment_mode: :pay_later,
        currency: session.currency(payload),
        subtotal_cents: session.cents(payload, "subtotal_cents", "subtotal_amount", "subtotal", "sub_total"),
        tax_cents: session.cents(payload, "tax_cents", "tax_amount", "tax"),
        fee_cents: session.cents(payload, "fee_cents", "fee_amount", "fees"),
        total_cents: session.cents(payload, "total_cents", "total_amount", "total", "amount"),
        fulfillment_status: session.fulfillment_status(payload),
        tags: Array(payload["tags"]).filter_map { |tag| tag.is_a?(Hash) ? tag["name"] : tag },
        metadata: order.metadata.merge("aryeo_id" => external, "aryeo_status" => session.value(payload, "status"))
      )
      order.save!
      session.records(payload, "items", "order_items", "product_items").each do |item|
        session.import_order_item(order, item)
      end
      session.import_payment_metadata(order, payload)
      session.import_order_appointments(order, payload) unless session.order_appointments_selected?
      order
    end

    def import_appointment
      external = session.external_id(payload)
      listing = session.listing_for(payload)
      return if external.blank? || listing.blank?

      appointment = session.appointment_record(external)
      starts_at = session.time_value(payload, "starts_at", "start_at", "scheduled_at", "start_time", "created_at", "updated_at")
      return if starts_at.blank?

      appointment ||= session.organization.appointments.build(listing:)
      appointment.assign_attributes(
        listing:,
        order: session.order_for(payload),
        assigned_user: session.staff_for(payload),
        status: session.appointment_status_for(payload),
        starts_at:,
        ends_at: session.time_value(payload, "ends_at", "end_at", "end_time") || starts_at + 1.hour,
        notes: [ session.value(payload, "notes", "description"), "[aryeo:#{external}]" ].compact.join("\n"),
        origin: :aryeo
      )
      appointment.save!
      appointment
    end

    def import_task
      external = session.external_id(payload)
      listing = session.listing_for(payload)
      return if external.blank? || listing.blank?

      task = session.task_record(external)
      task ||= session.organization.workflow_tasks.build(listing:, metadata: { "aryeo_id" => external })
      task.assign_attributes(
        listing:,
        title: session.value(payload, "title", "name").presence || "Aryeo task #{external}",
        description: session.value(payload, "description", "notes"),
        assignee: session.staff_for(payload),
        status: session.workflow_status(payload),
        priority: session.task_priority_for(payload),
        customer_visible: false,
        due_at: session.time_value(payload, "due_at", "due_date"),
        completed_at: session.time_value(payload, "completed_at"),
        origin: :aryeo,
        metadata: task.metadata.merge("aryeo_id" => external)
      )
      task.save!
      task
    end
  end
end

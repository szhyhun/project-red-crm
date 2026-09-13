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
      email = session.staff_value(payload, "email", "email_address").to_s.downcase
      return if email.blank?

      user = session.organization.users.find_by(email:)
      user ||= User.find_by(email:)
      return user if user&.organization_id == session.organization.id
      return if user.present?

      password = SecureRandom.urlsafe_base64(32)
      session.organization.users.create!(
        name: session.staff_person_name(payload).presence || email.split("@").first,
        email:,
        role: :production_staff,
        status: :suspended,
        password:,
        password_confirmation: password,
        origin: :aryeo
      )
    end

    def import_client
      external = session.customer_external_id(payload)
      return if external.blank?

      client = session.customer_record_for("clients", external)&.record ||
               session.organization.client_accounts.find_by("metadata ->> 'aryeo_id' = ?", external)
      client ||= session.organization.client_accounts.build(metadata: { "aryeo_id" => external })
      client.assign_attributes(
        name: session.customer_person_name(payload, "company_name").presence || "Aryeo client #{external}",
        email: session.customer_value(payload, "email", "email_address"),
        phone: session.customer_value(payload, "phone", "phone_number"),
        brokerage_name: session.customer_value(payload, "brokerage_name", "company"),
        kind: session.customer_kind(payload),
        origin: :aryeo,
        metadata: client.metadata.merge("aryeo_id" => external)
      )
      client.save!
      client
    end

    def import_customer_team
      external = session.customer_external_id(payload)
      return if external.blank?

      team = session.customer_record_for("customer_teams", external)&.record
      name = session.customer_value(payload, "name", "brokerage_name").presence || "Aryeo customer team #{external}"
      team ||= session.organization.customer_teams.find_by("lower(name) = ?", name.downcase)
      team ||= session.organization.customer_teams.build
      team.assign_attributes(
        name:,
        brokerage_name: session.customer_value(payload, "brokerage_name"),
        brokerage_website: session.customer_value(payload, "brokerage_website"),
        website: session.customer_value(payload, "website"),
        logo_url: session.customer_value(payload, "logo_url"),
        description: session.customer_value(payload, "description"),
        archived: session.customer_boolean_value(payload, "is_archived"),
        origin: :aryeo
      )
      team.save!

      session.customer_payloads(payload).each do |customer_payload|
        customer_id = session.customer_external_id(customer_payload)
        account = session.customer_record_for("clients", customer_id)&.record
        if customer_id.present? && account.blank? && session.customer_payload_has_profile?(customer_payload)
          account = session.customer_import_dependency(:clients, customer_payload)
        end
        team.customer_team_memberships.find_or_create_by!(client_account: account) if account
      end
      team
    end

    def import_product
      external = session.catalog_external_id(payload)
      return if external.blank?

      product = session.catalog_record_for("products", external)&.record ||
                session.organization.products.find_by(external_source: "aryeo", external_id: external)
      attributes = {
        title: session.catalog_value(payload, "title", "name").presence || "Aryeo product #{external}",
        description: session.catalog_value(payload, "description"),
        kind: session.catalog_product_kind(payload),
        deliverable_type: session.catalog_product_deliverable_type(payload),
        sla_days: session.catalog_integer_value(payload, "sla_days", "turnaround_days", "delivery_days") || 0,
        active: session.catalog_active?(payload),
        categories: Array(payload["categories"] || payload["category_names"] || payload.dig("category", "name")).compact,
        source_payload: ::Aryeo::PayloadSanitizer.call(payload),
        origin: :aryeo
      }
      product ||= session.organization.products.build(
        external_source: "aryeo",
        external_id: external,
        slug: session.catalog_unique_product_slug(attributes[:title], external)
      )
      product.assign_attributes(attributes)
      product.save!
      Array(payload["variants"] || payload["product_variants"] || payload["prices"]).each do |variant_payload|
        import_variant(product, session.catalog_stringify(variant_payload))
      end
      product
    end

    def import_variant(product, variant_payload)
      external = session.catalog_external_id(variant_payload)
      return if external.blank?

      variant = product.product_variants.find_or_initialize_by(external_id: external)
      sqft_min, sqft_max = session.catalog_sqft_range(variant_payload)
      variant.assign_attributes(
        title: session.catalog_value(variant_payload, "title", "name").presence || product.title,
        price_cents: session.catalog_cents(variant_payload, "price_cents", "price_amount", "unit_price_amount",
                                           "base_price_amount", "price", "amount"),
        duration_minutes: session.catalog_integer_value(variant_payload, "duration_minutes", "duration"),
        sqft_min:, sqft_max:,
        quantity_label: session.catalog_value(variant_payload, "quantity_label", "quantity_label_text", "label", "subtitle", "sub_title"),
        active: session.catalog_active?(variant_payload),
        source_payload: ::Aryeo::PayloadSanitizer.call(variant_payload)
      )
      variant.save!
    end

    def import_listing
      external = session.listing_external_id(payload)
      return if external.blank?

      listing = session.listing_record_for(external)
      related_clients = session.listing_clients(payload)
      client = related_clients.first || session.listing_client_for(payload) || session.listing_imported_client
      address = session.listing_stringify(payload["address"] || payload["property_address"] || {})
      listing ||= session.organization.listings.build(client_account: client, metadata: { "aryeo_id" => external })
      listing.assign_attributes(
        client_account: client,
        address_line_1: session.listing_value(address, "address_line_1", "line1", "street_address", "address").presence ||
          session.listing_value(payload, "address_line_1", "address").presence || "Aryeo listing #{external}",
        address_line_2: session.listing_value(address, "address_line_2", "line2", "unit"),
        city: session.listing_value(address, "city").presence || session.listing_value(payload, "city"),
        province: session.listing_value(address, "state", "province", "region").presence || session.listing_value(payload, "province", "state"),
        postal_code: session.listing_value(address, "postal_code", "zip", "zip_code").presence || session.listing_value(payload, "postal_code"),
        country: session.listing_value(address, "country", "country_code").presence || "CA",
        square_feet: session.listing_integer_value(payload, "square_feet", "sqft", "square_footage"),
        bedrooms: session.listing_integer_value(payload, "bedrooms"),
        bathrooms: session.listing_decimal_value(payload, "bathrooms"),
        mls_number: session.listing_value(payload, "mls_number", "mls_id"),
        status: session.listing_status(payload),
        delivery_status: session.listing_delivery_status(payload),
        scheduled_at: session.listing_time_value(payload, "scheduled_at", "appointment_at"),
        delivered_at: session.listing_time_value(payload, "delivered_at"),
        public_slug: session.listing_value(payload, "public_slug", "slug").presence || "aryeo-#{external}",
        tags: Array(payload["tags"]).filter_map { |tag| tag.is_a?(Hash) ? tag["name"] : tag },
        origin: :aryeo,
        metadata: listing.metadata.merge("aryeo_id" => external, "aryeo_status" => session.listing_value(payload, "status"))
      )
      listing.save!
      related_clients.drop(1).each do |related_client|
        listing.listing_customers.find_or_create_by!(client_account: related_client)
      end
      import_listing_media(listing)
      session.listing_import_relations(listing, payload)
      session.listing_import_property_site(listing, payload)
      listing
    end

    def import_listing_media(listing)
      ::Aryeo::ImportSession::LISTING_MEDIA.each do |key, category|
        session.media_records(payload, key).each do |media_payload|
          import_media_asset(listing, media_payload, category)
        rescue ActiveRecord::RecordInvalid => error
          session.media_increment("failed")
          session.media_record_error(
            "media_assets #{session.media_external_id(media_payload) || "unknown"}: #{error.message}"
          )
        end
      end
    end

    def import_media_asset(listing, media_payload, category)
      external = session.media_external_id(media_payload)
      return if external.blank?

      source_url = session.media_value(
        media_payload,
        *::Aryeo::ImportSession::MEDIA_SOURCE_KEYS.fetch(
          category, ::Aryeo::ImportSession::MEDIA_SOURCE_KEYS["files"]
        )
      ).to_s.presence
      asset = session.media_record_for(external)&.record
      asset ||= session.organization.media_assets.build(listing:, metadata: { "aryeo_id" => external })
      filename = session.media_filename(media_payload, external, source_url)
      metadata = asset.metadata.merge("aryeo_id" => external)
      if source_url.present?
        metadata["aryeo_source_url"] = source_url
        metadata.delete("processing_error")
      else
        metadata["processing_error"] = "missing_media_url"
        session.media_record_error("media_assets #{external}: Aryeo #{category} record has no downloadable URL")
      end
      content_type = session.media_content_type_for(category, media_payload, source_url)
      asset.assign_attributes(
        listing:,
        filename:,
        content_type:,
        byte_size: session.media_integer_value(media_payload, "byte_size", "filesize", "size"),
        width: session.media_integer_value(media_payload, "width"),
        height: session.media_integer_value(media_payload, "height"),
        duration_seconds: session.media_integer_value(media_payload, "duration_seconds", "duration"),
        category: session.media_category_for(category, content_type),
        position: session.media_integer_value(media_payload, "index", "order_index", "position") || 0,
        status: source_url.present? ? :pending : :failed,
        storage_key: asset.storage_key.presence || DeliveryStorage.key_for(organization: session.organization, listing:, filename:),
        source_url: nil,
        customer_visible: true,
        origin: :aryeo,
        metadata:
      )
      asset.save!
      session.media_increment(source_url.present? ? "queued" : "failed")
      external_record = session.media_archive(
        "media_assets", media_payload, record: asset, metadata: { "media_url" => source_url },
        sync_status: source_url.present? ? :pending_media_copy : :failed
      )
      ::AryeoMediaCopyJob.perform_later(external_record.id) if source_url.present? && !asset.ready?
    end

    def import_order
      external = session.order_external_id(payload)
      return if external.blank?

      listing = session.order_listing_for(payload)
      if listing.blank? && payload["listing"].is_a?(Hash)
        listing = session.order_import_dependency(:listings, session.order_stringify(payload["listing"]))
      end
      client = session.order_client_for(payload)
      client ||= session.order_import_client(payload)
      client ||= listing&.client_account || session.order_imported_client
      order = session.order_record_for(external)
      order ||= session.organization.orders.build(client_account: client, listing:, metadata: { "aryeo_id" => external })
      order.assign_attributes(
        client_account: client,
        listing:,
        source: "aryeo",
        origin: :aryeo,
        status: session.order_status(payload),
        payment_mode: :pay_later,
        currency: session.order_currency(payload),
        subtotal_cents: session.order_cents(payload, "subtotal_cents", "subtotal_amount", "subtotal", "sub_total"),
        tax_cents: session.order_cents(payload, "tax_cents", "tax_amount", "tax"),
        fee_cents: session.order_cents(payload, "fee_cents", "fee_amount", "fees"),
        total_cents: session.order_cents(payload, "total_cents", "total_amount", "total", "amount"),
        fulfillment_status: session.order_fulfillment_status(payload),
        tags: Array(payload["tags"]).filter_map { |tag| tag.is_a?(Hash) ? tag["name"] : tag },
        metadata: order.metadata.merge("aryeo_id" => external, "aryeo_status" => session.order_value(payload, "status"))
      )
      order.save!
      session.order_records(payload, "items", "order_items", "product_items").each do |item|
        session.order_import_item(order, item)
      end
      session.order_import_payment(order, payload)
      session.order_import_appointments(order, payload) unless session.order_appointments_selected?
      order
    end

    def import_appointment
      external = session.appointment_external_id(payload)
      listing = session.appointment_listing_for(payload)
      return if external.blank? || listing.blank?

      appointment = session.appointment_record_for(external)
      starts_at = session.appointment_time_value(payload, "starts_at", "start_at", "scheduled_at", "start_time", "created_at", "updated_at")
      return if starts_at.blank?

      appointment ||= session.organization.appointments.build(listing:)
      appointment.assign_attributes(
        listing:,
        order: session.appointment_order_for(payload),
        assigned_user: session.appointment_staff_for(payload),
        status: session.appointment_status(payload),
        starts_at:,
        ends_at: session.appointment_time_value(payload, "ends_at", "end_at", "end_time") || starts_at + 1.hour,
        notes: [ session.appointment_value(payload, "notes", "description"), "[aryeo:#{external}]" ].compact.join("\n"),
        origin: :aryeo
      )
      appointment.save!
      appointment
    end

    def import_task
      external = session.task_external_id(payload)
      listing = session.task_listing_for(payload)
      return if external.blank? || listing.blank?

      task = session.task_record_for(external)
      task ||= session.organization.workflow_tasks.build(listing:, metadata: { "aryeo_id" => external })
      task.assign_attributes(
        listing:,
        title: session.task_value(payload, "title", "name").presence || "Aryeo task #{external}",
        description: session.task_value(payload, "description", "notes"),
        assignee: session.task_staff_for(payload),
        status: session.task_workflow_status(payload),
        priority: session.task_priority(payload),
        customer_visible: false,
        due_at: session.task_time_value(payload, "due_at", "due_date"),
        completed_at: session.task_time_value(payload, "completed_at"),
        origin: :aryeo,
        metadata: task.metadata.merge("aryeo_id" => external)
      )
      task.save!
      task
    end
  end
end

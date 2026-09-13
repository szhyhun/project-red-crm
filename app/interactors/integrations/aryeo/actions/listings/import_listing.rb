module Integrations::Aryeo::Actions::Listings
  class ImportListing < ApplicationInteractor
      def call
        importer = context.fetch(:importer)
        payload = context.fetch(:payload)
        external = importer.listing_external_id(payload)
        return context.set(:listing, nil) if external.blank?

        listing = importer.listing_record_for(external)
        related_clients = importer.listing_clients(payload)
        client = related_clients.first || importer.listing_client_for(payload) || importer.listing_imported_client
        address = importer.listing_stringify(payload["address"] || payload["property_address"] || {})
        listing ||= importer.organization.listings.build(client_account: client, metadata: { "aryeo_id" => external })
        listing.assign_attributes(
          client_account: client,
          address_line_1: importer.listing_value(address, "address_line_1", "line1", "street_address", "address").presence ||
            importer.listing_value(payload, "address_line_1", "address").presence || "Aryeo listing #{external}",
          address_line_2: importer.listing_value(address, "address_line_2", "line2", "unit"),
          city: importer.listing_value(address, "city").presence || importer.listing_value(payload, "city"),
          province: importer.listing_value(address, "state", "province", "region").presence || importer.listing_value(payload, "province", "state"),
          postal_code: importer.listing_value(address, "postal_code", "zip", "zip_code").presence || importer.listing_value(payload, "postal_code"),
          country: importer.listing_value(address, "country", "country_code").presence || "CA",
          square_feet: importer.listing_integer_value(payload, "square_feet", "sqft", "square_footage"),
          bedrooms: importer.listing_integer_value(payload, "bedrooms"),
          bathrooms: importer.listing_decimal_value(payload, "bathrooms"),
          mls_number: importer.listing_value(payload, "mls_number", "mls_id"),
          status: importer.listing_status(payload),
          delivery_status: importer.listing_delivery_status(payload),
          scheduled_at: importer.listing_time_value(payload, "scheduled_at", "appointment_at"),
          delivered_at: importer.listing_time_value(payload, "delivered_at"),
          public_slug: importer.listing_value(payload, "public_slug", "slug").presence || "aryeo-#{external}",
          tags: Array(payload["tags"]).filter_map { |tag| tag.is_a?(Hash) ? tag["name"] : tag },
          origin: :aryeo,
          metadata: listing.metadata.merge("aryeo_id" => external, "aryeo_status" => importer.listing_value(payload, "status"))
        )
        listing.save!
        related_clients.drop(1).each do |related_client|
          listing.listing_customers.find_or_create_by!(client_account: related_client)
        end
        importer.listing_import_media(listing, payload)
        importer.listing_import_relations(listing, payload)
        importer.listing_import_property_site(listing, payload)

        context.set(:listing, listing)
      end
  end
end

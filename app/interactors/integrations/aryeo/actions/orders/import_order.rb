module Integrations::Aryeo::Actions::Orders
  class ImportOrder < ApplicationInteractor
      def call
        importer = context.fetch(:importer)
        payload = context.fetch(:payload)
        external = importer.order_external_id(payload)
        return context.set(:order, nil) if external.blank?

        listing = importer.order_listing_for(payload)
        if listing.blank? && payload["listing"].is_a?(Hash)
          listing = importer.order_import_dependency(:listings, importer.order_stringify(payload["listing"]))
        end
        client = importer.order_client_for(payload)
        client ||= importer.order_import_client(payload)
        client ||= listing&.client_account || importer.order_imported_client
        order = importer.order_record_for(external)
        order ||= importer.organization.orders.build(client_account: client, listing:, metadata: { "aryeo_id" => external })
        order.assign_attributes(
          client_account: client,
          listing:,
          source: "aryeo",
          origin: :aryeo,
          status: importer.order_status(payload),
          payment_mode: :pay_later,
          currency: importer.order_currency(payload),
          subtotal_cents: importer.order_cents(payload, "subtotal_cents", "subtotal_amount", "subtotal", "sub_total"),
          tax_cents: importer.order_cents(payload, "tax_cents", "tax_amount", "tax"),
          fee_cents: importer.order_cents(payload, "fee_cents", "fee_amount", "fees"),
          total_cents: importer.order_cents(payload, "total_cents", "total_amount", "total", "amount"),
          fulfillment_status: importer.order_fulfillment_status(payload),
          tags: Array(payload["tags"]).filter_map { |tag| tag.is_a?(Hash) ? tag["name"] : tag },
          metadata: order.metadata.merge("aryeo_id" => external, "aryeo_status" => importer.order_value(payload, "status"))
        )
        order.save!
        importer.order_records(payload, "items", "order_items", "product_items").each do |item|
          importer.order_import_item(order, item)
        end
        importer.order_import_payment(order, payload)
        importer.order_import_appointments(order, payload) unless importer.order_appointments_selected?

        context.set(:order, order)
      end
  end
end

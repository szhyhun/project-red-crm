module Integrations::Aryeo::Actions::Catalog
  class ImportProduct < ApplicationInteractor
      def call
        importer = context.fetch(:importer)
        payload = context.fetch(:payload)
        external = importer.catalog_external_id(payload)
        return context.set(:product, nil) if external.blank?

        product = importer.catalog_record_for("products", external)&.record ||
                  importer.organization.products.find_by(external_source: "aryeo", external_id: external)
        attributes = {
          title: importer.catalog_value(payload, "title", "name").presence || "Aryeo product #{external}",
          description: importer.catalog_value(payload, "description"),
          kind: importer.catalog_product_kind(payload),
          deliverable_type: importer.catalog_product_deliverable_type(payload),
          sla_days: importer.catalog_integer_value(payload, "sla_days", "turnaround_days", "delivery_days") || 0,
          active: importer.catalog_active?(payload),
          categories: Array(payload["categories"] || payload["category_names"] || payload.dig("category", "name")).compact,
          source_payload: ::Aryeo::PayloadSanitizer.call(payload),
          origin: :aryeo
        }
        product ||= importer.organization.products.build(
          external_source: "aryeo",
          external_id: external,
          slug: importer.catalog_unique_product_slug(attributes[:title], external)
        )
        product.assign_attributes(attributes)
        product.save!

        Array(payload["variants"] || payload["product_variants"] || payload["prices"]).each do |variant_payload|
          result = ImportVariant.call(
            importer:,
            product:,
            payload: importer.catalog_stringify(variant_payload)
          )
          raise result.failure.original_error || result.failure if result.failure?
        end

        context.set(:product, product)
      end
  end
end

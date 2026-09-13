module Integrations::Aryeo::Actions::Catalog
  class ImportVariant < ApplicationInteractor
      def call
        importer = context.fetch(:importer)
        product = context.fetch(:product)
        payload = context.fetch(:payload)
        external = importer.catalog_external_id(payload)
        return context.set(:variant, nil) if external.blank?

        variant = product.product_variants.find_or_initialize_by(external_id: external)
        sqft_min, sqft_max = importer.catalog_sqft_range(payload)
        variant.assign_attributes(
          title: importer.catalog_value(payload, "title", "name").presence || product.title,
          price_cents: importer.catalog_cents(payload, "price_cents", "price_amount", "unit_price_amount",
                                              "base_price_amount", "price", "amount"),
          duration_minutes: importer.catalog_integer_value(payload, "duration_minutes", "duration"),
          sqft_min:, sqft_max:,
          quantity_label: importer.catalog_value(payload, "quantity_label", "quantity_label_text", "label", "subtitle", "sub_title"),
          active: importer.catalog_active?(payload),
          source_payload: ::Aryeo::PayloadSanitizer.call(payload)
        )
        variant.save!

        context.set(:variant, variant)
      end
  end
end

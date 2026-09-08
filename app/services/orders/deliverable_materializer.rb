module Orders
  class DeliverableMaterializer
    def initialize(order:)
      @order = order
    end

    def call
      position = 0
      @order.order_items.includes(:product, :product_variant).order(:id).each do |order_item|
        next if order_item.cancelled? || order_item.product.blank?

        if order_item.product.package?
          package_components_for(order_item).each do |component, service_product, component_snapshot|
            create_deliverable(order_item:, component:, service_product:, component_snapshot:, position: position)
            position += 1
          end
        elsif order_item.product.service? || order_item.product.addon?
          create_deliverable(order_item:, position: position)
          position += 1
        end
      end

      @order.order_deliverables.ordered
    end

    private

    def package_components_for(order_item)
      current_components = order_item.product.package_components.ordered.includes(:service_product).to_a
      snapshot_components = Array(order_item.snapshot.to_h.stringify_keys["components"]).filter_map(&:to_h)
      return current_components.map { |component| [ component, component.service_product, nil ] } if snapshot_components.empty?

      snapshot_components.filter_map do |component_snapshot|
        service_product = order_item.order.organization.products.find_by(id: component_snapshot["service_product_id"])
        next if service_product.blank?

        component = current_components.find do |record|
          record.id == component_snapshot["component_id"].to_i && record.service_product_id == service_product.id
        end ||
                    current_components.find { |record| record.service_product_id == service_product.id }
        [ component, service_product, component_snapshot ]
      end
    end

    def create_deliverable(order_item:, component: nil, service_product: nil, component_snapshot: nil, position:)
      service_product ||= component&.service_product || order_item.product
      catalog = service_catalog_snapshot(order_item:, component:, service_product:, component_snapshot:)
      scope = order_scope(order_item)
      component_key = component_snapshot&.fetch("component_id", nil) || component&.id || "standalone"
      key = [ "order", @order.id, "item", order_item.id, "component", component_key ].join(":")
      deliverable = @order.order_deliverables.find_by(materialization_key: key)
      return deliverable if deliverable.present?

      metadata = { "quantity" => order_item.quantity }
      if component.present? || component_snapshot.present?
        metadata["component_quantity"] = catalog.fetch("quantity", component&.quantity || 1)
        metadata["package_component_id"] = component_snapshot["component_id"] if component_snapshot&.key?("component_id")
      end

      deliverable = @order.order_deliverables.build(
        organization: @order.organization,
        listing: @order.listing,
        order_item:,
        product_component: component,
        service_product:,
        materialization_key: key,
        title: catalog.fetch("title", service_product.title),
        description: catalog.key?("description") ? catalog["description"] : service_product.description,
        deliverable_type: catalog.fetch("deliverable_type", service_product.deliverable_type),
        sla_days: catalog.fetch("sla_days", service_product.sla_days),
        scope_sqft_min: scope[:sqft_min],
        scope_sqft_max: scope[:sqft_max],
        scope_label: scope[:label],
        position:,
        target_on: target_on(catalog.fetch("sla_days", service_product.sla_days)),
        metadata:
      )
      deliverable.save!
      deliverable
    end

    def order_scope(order_item)
      snapshot = order_item.snapshot.to_h.stringify_keys
      variant = order_item.product_variant
      minimum = snapshot.key?("sqft_min") ? snapshot["sqft_min"] : variant&.sqft_min
      maximum = snapshot.key?("sqft_max") ? snapshot["sqft_max"] : variant&.sqft_max
      quantity_label = snapshot.key?("quantity_label") ? snapshot["quantity_label"] : variant&.quantity_label
      variant_title = snapshot["variant_title"].presence || variant&.title

      {
        sqft_min: minimum,
        sqft_max: maximum,
        label: scope_label(minimum:, maximum:, quantity_label:, variant_title:)
      }
    end

    def service_catalog_snapshot(order_item:, component:, service_product:, component_snapshot: nil)
      snapshot = order_item.snapshot.to_h.stringify_keys

      return component_snapshot if component_snapshot.present?

      if component.present?
        component_snapshot = Array(snapshot["components"]).filter_map(&:to_h).find do |entry|
          entry["service_product_id"].to_i == service_product.id
        end

        return component_snapshot if component_snapshot.present?
      end

      {
        "title" => snapshot["product_title"].presence || service_product.title,
        "description" => snapshot.key?("product_description") ? snapshot["product_description"] : service_product.description,
        "deliverable_type" => snapshot["product_deliverable_type"].presence || service_product.deliverable_type,
        "sla_days" => snapshot.key?("product_sla_days") ? snapshot["product_sla_days"] : service_product.sla_days
      }
    end

    def target_on(sla_days)
      date = @order.approved_at&.in_time_zone(@order.organization.time_zone)&.to_date || Time.current.in_time_zone(@order.organization.time_zone).to_date
      remaining = sla_days.to_i
      while remaining.positive?
        date += 1.day
        remaining -= 1 unless date.saturday? || date.sunday?
      end
      date
    end

    def scope_label(minimum:, maximum:, quantity_label:, variant_title:)
      return quantity_label if quantity_label.present?
      return "#{ActiveSupport::NumberHelper.number_to_delimited(minimum)}–#{ActiveSupport::NumberHelper.number_to_delimited(maximum)} sqft" if minimum.present? && maximum.present?
      return "#{ActiveSupport::NumberHelper.number_to_delimited(minimum)}+ sqft" if minimum.present?
      return "Up to #{ActiveSupport::NumberHelper.number_to_delimited(maximum)} sqft" if maximum.present?

      variant_title
    end
  end
end

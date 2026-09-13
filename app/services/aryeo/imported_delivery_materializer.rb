require "set"

module Aryeo
  class ImportedDeliveryMaterializer
    MEDIA_DELIVERABLE_TYPES = {
      "images" => %w[photography drone],
      "videos" => %w[video vertical_reel],
      "floor_plans" => [ "floor_plan" ],
      "tours" => [ "tour" ],
      "files" => [ "files", "property_site", "other" ]
    }.freeze

    def initialize(run:)
      @run = run
      @organization = run.organization
      @order_records = source_records("orders")
      @media_records = source_records("media_assets")
      @linked_deliverable_ids = Set.new
    end

    def call
      orders = imported_orders
      deliverables_by_order = orders.each_with_object({}) do |order, result|
        deliverables = materialize_order(order)
        result[order] = deliverables if deliverables.present?
      end

      linked_assets = link_media_assets(deliverables_by_order)
      delivered_deliverables = mark_media_deliverables_delivered(deliverables_by_order)
      enqueue_workflows(deliverables_by_order)

      {
        orders: deliverables_by_order.keys,
        deliverables: deliverables_by_order.values.flatten,
        linked_media_assets: linked_assets,
        delivered_deliverables:
      }
    end

    private

    def source_records(resource_type)
      @run.external_records.where(resource_type:).includes(:record).filter_map do |external_record|
        next unless external_record.record.present?

        external_record
      end
    end

    def imported_orders
      @order_records.filter_map do |external_record|
        order = external_record.record
        order if order.is_a?(Order) && order.organization_id == @organization.id && !order.cancelled?
      end.uniq
    end

    def materialize_order(order)
      return [] unless order.order_items.includes(:product).any? { |item| item.product.present? }

      # Aryeo can expose a submitted order and its media in the same listing
      # response. Materialize the production graph here instead of waiting for
      # the local approval endpoint; otherwise imported files have nowhere to
      # belong and the portal has to collapse them into one generic card.
      ::Orders::DeliverableMaterializer.new(order:).call
    end

    def link_media_assets(deliverables_by_order)
      @media_records.each_with_object([]) do |external_record, linked_assets|
        asset = external_record.record
        next unless asset.is_a?(MediaAsset)
        next unless asset.organization_id == @organization.id && asset.order_deliverable.blank?

        order = order_for(asset, external_record.source_payload, deliverables_by_order.keys)
        next if order.blank?

        deliverables = deliverables_by_order.fetch(order, [])
        deliverable = deliverable_for(asset, external_record.source_payload, deliverables)
        next if deliverable.blank?

        asset.update!(order:, order_item: deliverable.order_item, order_deliverable: deliverable)
        @linked_deliverable_ids << deliverable.id
        linked_assets << asset
      end
    end

    def order_for(asset, payload, orders)
      external = external_reference(payload, "order_id", "order_uuid", "order")
      return orders.find { |order| order_external_id(order) == external } if external.present?

      listing_orders = orders.select { |order| order.listing_id == asset.listing_id }
      listing_orders.one? ? listing_orders.first : nil
    end

    def deliverable_for(asset, payload, deliverables)
      return if deliverables.empty?

      item_external = external_reference(payload, "order_item_id", "item_id", "order_item", "item")
      if item_external.present?
        item = deliverables.find { |deliverable| order_item_external_id(deliverable.order_item) == item_external }
        return item if item.present?
      end

      product_external = external_reference(payload, "service_product_id", "product_id", "service_id",
                                             "service_product", "product", "service")
      if product_external.present?
        product = deliverables.find do |deliverable|
          deliverable.service_product.external_id.to_s == product_external
        end
        return product if product.present?
      end

      compatible_types = MEDIA_DELIVERABLE_TYPES.fetch(asset.category, [ "other" ])
      compatible = deliverables.select { |deliverable| compatible_types.include?(deliverable.deliverable_type) }
      return if compatible.empty?

      compatible.find { |deliverable| deliverable.deliverable_type == compatible_types.first } ||
        compatible.min_by { |deliverable| [ deliverable.position, deliverable.id ] }
    end

    def mark_media_deliverables_delivered(deliverables_by_order)
      deliverables_by_order.sum([]) do |order, deliverables|
        delivered_at = source_delivery_time(order)
        deliverables.filter_map do |deliverable|
          next unless source_fulfilled?(order) || @linked_deliverable_ids.include?(deliverable.id)
          next if deliverable.delivered?

          deliverable.update!(status: :delivered, delivered_at: delivered_at || deliverable.delivered_at || order.updated_at)
          deliverable
        end
      end
    end

    def enqueue_workflows(deliverables_by_order)
      deliverables_by_order.each_key do |order|
        next unless workflow_eligible?(order)

        ::Workflows::Trigger.new(order: order.reload).enqueue!
      end
    end

    def workflow_eligible?(order)
      return true if order.approved? || order.fulfilled?

      source_status(order).match?(/approve|paid|invoice|fulfill|deliver|complete/)
    end

    def source_fulfilled?(order)
      order.fulfilled? || source_status(order).match?(/fulfill|deliver|complete/)
    end

    def source_delivery_time(order)
      external_record_for(order)&.source_payload.to_h.then do |payload|
        parse_time(payload["delivered_at"] || payload["fulfilled_at"] || payload["completed_at"] || payload["updated_at"])
      end
    end

    def source_status(order)
      external_record_for(order)&.source_payload.to_h.fetch("status", "").to_s.downcase
    end

    def external_record_for(order)
      @order_records.find { |external_record| external_record.record_id == order.id }
    end

    def order_external_id(order)
      order.metadata.to_h.stringify_keys["aryeo_id"].to_s
    end

    def order_item_external_id(order_item)
      order_item.options.to_h.stringify_keys["aryeo_id"].to_s
    end

    def external_reference(payload, *keys)
      payload = payload.to_h.stringify_keys
      keys.each do |key|
        raw = payload[key]
        if raw.is_a?(Hash)
          nested_id = raw["id"] || raw["uuid"] || raw["external_id"]
          return nested_id.to_s if nested_id.present?
        elsif raw.present?
          return raw.to_s
        end
      end
      nil
    end

    def parse_time(value)
      return if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end

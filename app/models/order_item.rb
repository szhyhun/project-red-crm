class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product, optional: true
  belongs_to :product_variant, optional: true
  has_many :media_assets, dependent: :nullify
  has_many :order_deliverables, dependent: :destroy

  validates :title, presence: true
  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price_cents, :total_cents, numericality: { greater_than_or_equal_to: 0 }

  def cancelled?
    cancelled_at.present?
  end

  # Orders must retain the catalog scope that was sold even if a product
  # variant is later edited. The snapshot is deliberately relationally
  # independent from the mutable catalog row.
  def self.catalog_snapshot(variant, price_cents: variant.price_cents)
    product = variant.product
    snapshot = {
      product_title: product.title,
      product_description: product.description,
      product_deliverable_type: product.deliverable_type,
      product_sla_days: product.sla_days,
      variant_title: variant.title,
      price_cents:,
      sqft_min: variant.sqft_min,
      sqft_max: variant.sqft_max,
      quantity_label: variant.quantity_label
    }

    return snapshot unless product.package?

    snapshot.merge(
      components: product.package_components.ordered.includes(:service_product).map do |component|
        service_product = component.service_product

        {
          component_id: component.id,
          service_product_id: service_product.id,
          title: service_product.title,
          description: service_product.description,
          deliverable_type: service_product.deliverable_type,
          sla_days: service_product.sla_days,
          quantity: component.quantity,
          position: component.position
        }
      end
    )
  end
end

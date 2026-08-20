class PricingPlanPrice < ApplicationRecord
  belongs_to :pricing_plan
  belongs_to :product_variant

  validates :product_variant_id, uniqueness: { scope: :pricing_plan_id }
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :product_variant_belongs_to_plan_organization

  private

  def product_variant_belongs_to_plan_organization
    return if pricing_plan.blank? || product_variant.blank? || product_variant.product.organization_id == pricing_plan.organization_id

    errors.add(:product_variant, "must belong to the pricing plan organization")
  end
end

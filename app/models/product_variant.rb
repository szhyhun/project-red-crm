class ProductVariant < ApplicationRecord
  belongs_to :product
  has_many :pricing_plan_prices, dependent: :restrict_with_error

  scope :active, -> { where(active: true) }

  validates :title, presence: true
  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :sqft_min, :sqft_max, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :valid_sqft_range
  validate :active_sqft_range_does_not_overlap

  private

  def valid_sqft_range
    return if sqft_min.blank? || sqft_max.blank? || sqft_max >= sqft_min

    errors.add(:sqft_max, "must be greater than or equal to the minimum square footage")
  end

  # A relational row keeps each price tier addressable for orders, plans, and
  # historical snapshots. Overlap validation prevents an ambiguous checkout.
  def active_sqft_range_does_not_overlap
    return unless active? && (sqft_min.present? || sqft_max.present?) && product.present?

    overlap_scope = product.product_variants.where(active: true).where.not(id: id)
    overlap_conditions = []
    overlap_values = []

    if sqft_max.present?
      overlap_conditions << "(sqft_min IS NULL OR sqft_min <= ?)"
      overlap_values << sqft_max
    end

    if sqft_min.present?
      overlap_conditions << "(sqft_max IS NULL OR sqft_max >= ?)"
      overlap_values << sqft_min
    end

    overlap = overlap_scope.where(overlap_conditions.join(" AND "), *overlap_values).exists?
    errors.add(:base, "This range overlaps another active range.") if overlap
  end
end

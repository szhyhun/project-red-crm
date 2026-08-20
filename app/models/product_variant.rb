class ProductVariant < ApplicationRecord
  belongs_to :product
  has_many :pricing_plan_prices, dependent: :restrict_with_error

  scope :active, -> { where(active: true) }

  validates :title, presence: true
  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }
end

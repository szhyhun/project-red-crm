class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product, optional: true
  belongs_to :product_variant, optional: true
  has_many :media_assets, dependent: :nullify

  validates :title, presence: true
  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price_cents, :total_cents, numericality: { greater_than_or_equal_to: 0 }

  def cancelled?
    cancelled_at.present?
  end
end

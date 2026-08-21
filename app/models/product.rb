class Product < ApplicationRecord
  belongs_to :organization
  has_many :product_variants, dependent: :destroy
  accepts_nested_attributes_for :product_variants, allow_destroy: false

  enum :kind, { package: "package", service: "service", addon: "addon" }, validate: true

  validates :slug, :title, presence: true
  # The database enforces this per organization; validating it here turns a
  # duplicate slug into a 422 with a field error instead of a 500.
  validates :slug, uniqueness: { scope: :organization_id }

  def variant_for_sqft(sqft)
    product_variants.active.find do |variant|
      variant.sqft_min.present? && variant.sqft_max.present? &&
        sqft.between?(variant.sqft_min, variant.sqft_max)
    end || product_variants.active.find { |variant| variant.sqft_min.blank? && variant.sqft_max.blank? }
  end
end

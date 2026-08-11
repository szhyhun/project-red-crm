class Product < ApplicationRecord
  belongs_to :organization
  has_many :product_variants, dependent: :destroy
  accepts_nested_attributes_for :product_variants, allow_destroy: false

  enum :kind, { package: "package", service: "service", addon: "addon" }, validate: true

  validates :slug, :title, presence: true

  def variant_for_sqft(sqft)
    product_variants.active.find do |variant|
      variant.sqft_min.present? && variant.sqft_max.present? &&
        sqft.between?(variant.sqft_min, variant.sqft_max)
    end || product_variants.active.find { |variant| variant.sqft_min.blank? && variant.sqft_max.blank? }
  end
end

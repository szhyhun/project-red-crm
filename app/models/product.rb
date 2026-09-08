class Product < ApplicationRecord
  DELIVERABLE_TYPES = %w[photography video vertical_reel drone floor_plan tour property_site files other].freeze

  belongs_to :organization
  has_many :product_variants, dependent: :destroy
  has_many :package_components, class_name: "ProductComponent", foreign_key: :package_product_id,
           dependent: :destroy, inverse_of: :package_product
  has_many :service_components, class_name: "ProductComponent", foreign_key: :service_product_id,
           dependent: :restrict_with_error, inverse_of: :service_product
  accepts_nested_attributes_for :product_variants, allow_destroy: false

  enum :kind, { package: "package", service: "service", addon: "addon" }, validate: true

  validates :slug, :title, presence: true
  validates :deliverable_type, inclusion: { in: DELIVERABLE_TYPES }
  validates :sla_days, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  # The database enforces this per organization; validating it here turns a
  # duplicate slug into a 422 with a field error instead of a 500.
  validates :slug, uniqueness: { scope: :organization_id }

  def variant_for_sqft(sqft)
    return product_variants.active.find { |variant| variant.sqft_min.blank? && variant.sqft_max.blank? } if sqft.blank?

    product_variants.active.find do |variant|
      minimum_matches = variant.sqft_min.blank? || sqft >= variant.sqft_min
      maximum_matches = variant.sqft_max.blank? || sqft <= variant.sqft_max
      (variant.sqft_min.present? || variant.sqft_max.present?) && minimum_matches && maximum_matches
    end || product_variants.active.find { |variant| variant.sqft_min.blank? && variant.sqft_max.blank? }
  end

  def package?
    kind == "package"
  end
end

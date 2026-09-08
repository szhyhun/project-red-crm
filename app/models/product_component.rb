class ProductComponent < ApplicationRecord
  belongs_to :organization
  belongs_to :package_product, class_name: "Product", inverse_of: :package_components
  belongs_to :service_product, class_name: "Product", inverse_of: :service_components

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :service_product_id, uniqueness: { scope: :package_product_id }
  validate :package_must_be_a_package
  validate :service_must_not_be_a_package
  validate :products_belong_to_same_organization
  validate :package_cannot_include_itself

  scope :ordered, -> { order(:position, :id) }

  private

  def package_must_be_a_package
    return if package_product.blank? || package_product.package?

    errors.add(:package_product, "must be a package product")
  end

  def service_must_not_be_a_package
    return if service_product.blank? || !service_product.package?

    errors.add(:service_product, "cannot be another package")
  end

  def products_belong_to_same_organization
    return if package_product.blank? || service_product.blank? || organization.blank?
    return if package_product.organization_id == organization_id && service_product.organization_id == organization_id

    errors.add(:base, "products must belong to the same organization")
  end

  def package_cannot_include_itself
    errors.add(:service_product, "cannot be the package itself") if package_product_id.present? && package_product_id == service_product_id
  end
end

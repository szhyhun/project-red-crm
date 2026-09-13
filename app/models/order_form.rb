class OrderForm < ApplicationRecord
  belongs_to :organization
  has_many :order_form_products, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :order_form
  has_many :products, through: :order_form_products
  has_many :client_accounts, dependent: :nullify

  scope :active, -> { where(active: true) }

  validates :name, presence: true, uniqueness: { scope: :organization_id }
  validate :products_belong_to_organization

  # Replaces the services on the form, in the order given.
  def product_ids=(ids)
    wanted = Array(ids).compact_blank.map(&:to_i).uniq
    kept = order_form_products.reject { |row| wanted.exclude?(row.product_id) || row.marked_for_destruction? }
    order_form_products.each { |row| row.mark_for_destruction if wanted.exclude?(row.product_id) }
    wanted.each_with_index do |product_id, position|
      row = kept.find { |candidate| candidate.product_id == product_id } || order_form_products.build(product_id:)
      row.position = position
    end
  end

  def product_ids
    order_form_products.reject(&:marked_for_destruction?).map(&:product_id)
  end

  private

  def products_belong_to_organization
    foreign = Product.where(id: product_ids).where.not(organization_id:).exists?
    errors.add(:products, "must belong to the same organization") if foreign
  end
end

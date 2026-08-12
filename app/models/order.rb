class Order < ApplicationRecord
  belongs_to :organization
  belongs_to :client_account
  belongs_to :listing, optional: true
  has_many :order_items, dependent: :destroy
  has_many :media_assets, dependent: :nullify
  has_many :invoices, dependent: :nullify
  accepts_nested_attributes_for :order_items

  enum :status, { draft: "draft", submitted: "submitted", approved: "approved", invoiced: "invoiced", paid: "paid", cancelled: "cancelled" }, validate: true
  enum :payment_mode, { pay_now: "pay_now", pay_later: "pay_later" }, validate: true
  enum :discount_type, { fixed: "fixed", percentage: "percentage" }, validate: true
  enum :fulfillment_status, {
    unfulfilled: "unfulfilled", partially_fulfilled: "partially_fulfilled", fulfilled: "fulfilled"
  }, validate: true

  validates :currency, presence: true
  validates :discount_cents, :discount_rate_basis_points, :tax_cents, :fee_cents,
            numericality: { greater_than_or_equal_to: 0 }
  validates :discount_rate_basis_points, numericality: { less_than_or_equal_to: 10_000 }, if: :percentage?
  validate :related_records_belong_to_organization

  def recalculate_totals!
    self.subtotal_cents = order_items.to_a.reject(&:cancelled?).sum(&:total_cents)
    self.discount_cents = percentage? ? (subtotal_cents * discount_rate_basis_points / 10_000.0).round : discount_cents
    self.total_cents = [ subtotal_cents - discount_cents + tax_cents + fee_cents, 0 ].max
  end

  def payment_status
    active_invoices = invoices.reject(&:void?)
    return "unpaid" if active_invoices.empty?

    return "paid" if active_invoices.all? { |invoice| invoice.balance_due_cents.zero? }
    return "partially_paid" if active_invoices.any? { |invoice| invoice.total_cents.to_i > invoice.balance_due_cents.to_i }

    "unpaid"
  end

  def balance_due_cents
    invoices.reject(&:void?).sum { |invoice| invoice.balance_due_cents.to_i }
  end

  private

  def related_records_belong_to_organization
    errors.add(:client_account, "must belong to the same organization") if client_account.present? && client_account.organization_id != organization_id
    errors.add(:listing, "must belong to the same organization") if listing.present? && listing.organization_id != organization_id
  end
end

class Order < ApplicationRecord
  belongs_to :organization
  belongs_to :client_account
  belongs_to :listing, optional: true
  has_many :order_items, dependent: :destroy
  has_many :invoices, dependent: :nullify
  accepts_nested_attributes_for :order_items

  enum :status, { draft: "draft", submitted: "submitted", approved: "approved", invoiced: "invoiced", paid: "paid", cancelled: "cancelled" }, validate: true
  enum :payment_mode, { pay_now: "pay_now", pay_later: "pay_later" }, validate: true

  validates :currency, presence: true
  validate :related_records_belong_to_organization

  def recalculate_totals!
    self.subtotal_cents = order_items.to_a.sum(&:total_cents)
    self.total_cents = subtotal_cents - discount_cents + tax_cents
  end

  private

  def related_records_belong_to_organization
    errors.add(:client_account, "must belong to the same organization") if client_account.present? && client_account.organization_id != organization_id
    errors.add(:listing, "must belong to the same organization") if listing.present? && listing.organization_id != organization_id
  end
end

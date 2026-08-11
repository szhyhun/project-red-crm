class Order < ApplicationRecord
  belongs_to :organization
  belongs_to :client_account
  belongs_to :listing, optional: true
  has_many :order_items, dependent: :destroy
  accepts_nested_attributes_for :order_items

  enum :status, { draft: "draft", submitted: "submitted", approved: "approved", invoiced: "invoiced", paid: "paid", cancelled: "cancelled" }, validate: true
  enum :payment_mode, { pay_now: "pay_now", pay_later: "pay_later" }, validate: true

  validates :currency, presence: true

  def recalculate_totals!
    self.subtotal_cents = order_items.sum(:total_cents)
    self.total_cents = subtotal_cents - discount_cents + tax_cents
  end
end

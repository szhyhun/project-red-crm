class Payment < ApplicationRecord
  belongs_to :invoice
  belongs_to :organization

  enum :status, { pending: "pending", succeeded: "succeeded", failed: "failed", refunded: "refunded" }, validate: true

  validates :provider, :amount_cents, :currency, presence: true
  validate :invoice_belongs_to_organization

  private

  def invoice_belongs_to_organization
    return if invoice.blank? || invoice.organization_id == organization_id

    errors.add(:invoice, "must belong to the same organization")
  end
end

class Invoice < ApplicationRecord
  belongs_to :organization
  belongs_to :client_account
  belongs_to :listing, optional: true
  belongs_to :order, optional: true
  has_many :payments, dependent: :restrict_with_error

  enum :status, { draft: "draft", sent: "sent", partially_paid: "partially_paid", paid: "paid", void: "void", overdue: "overdue" }, validate: true

  validates :number, presence: true
  validates :balance_due_cents, numericality: { greater_than_or_equal_to: 0 }
  validate :related_records_belong_to_organization

  def sendable?
    draft? || sent? || overdue?
  end

  private

  def related_records_belong_to_organization
    errors.add(:client_account, "must belong to the same organization") if client_account.present? && client_account.organization_id != organization_id
    errors.add(:listing, "must belong to the same organization") if listing.present? && listing.organization_id != organization_id
    errors.add(:order, "must belong to the same organization") if order.present? && order.organization_id != organization_id
  end
end

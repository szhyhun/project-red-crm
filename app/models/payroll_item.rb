class PayrollItem < ApplicationRecord
  belongs_to :organization
  belongs_to :listing
  belongs_to :order, optional: true
  belongs_to :order_item, optional: true
  belongs_to :team_member, class_name: "User", optional: true
  belongs_to :created_by, class_name: "User"

  enum :status, {
    draft: "draft", submitted: "submitted", included_in_pay_run: "included_in_pay_run",
    paid: "paid", cancelled: "cancelled"
  }, validate: true

  validates :title, presence: true
  validates :amount_cents, numericality: { greater_than_or_equal_to: 0 }
  validate :records_belong_to_organization
  validate :order_belongs_to_listing
  validate :order_item_belongs_to_order
  before_validation :derive_status_from_dates

  private

  def records_belong_to_organization
    errors.add(:listing, "must belong to the same organization") if listing.present? && listing.organization_id != organization_id
    errors.add(:order, "must belong to the same organization") if order.present? && order.organization_id != organization_id
    errors.add(:team_member, "must belong to the same organization") if team_member.present? && team_member.organization_id != organization_id
    errors.add(:created_by, "must belong to the same organization") if created_by.present? && created_by.organization_id != organization_id
  end

  def order_belongs_to_listing
    return if listing.blank? || order.blank? || order.listing_id == listing_id

    errors.add(:order, "must belong to this listing")
  end

  def order_item_belongs_to_order
    return if order_item.blank? || order.blank? || order_item.order_id == order_id

    errors.add(:order_item, "must belong to the selected order")
  end

  def derive_status_from_dates
    return if paid? || cancelled? || included_in_pay_run?

    self.status = submitted_at.present? ? "submitted" : "draft"
  end
end

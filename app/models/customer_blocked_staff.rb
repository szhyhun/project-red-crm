class CustomerBlockedStaff < ApplicationRecord
  self.table_name = "customer_blocked_staff"

  belongs_to :customer, class_name: "User"
  belongs_to :staff, class_name: "User"

  validates :staff_id, uniqueness: { scope: :customer_id }
  validate :customer_blocks_their_own_organizations_staff

  private

  def customer_blocks_their_own_organizations_staff
    return if customer.blank? || staff.blank?

    errors.add(:customer, "must be a customer") if customer.internal?
    errors.add(:staff, "must be staff in the same organization") unless staff.internal? && staff.organization_id == customer.organization_id
  end
end

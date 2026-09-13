class AppointmentTeamMember < ApplicationRecord
  belongs_to :appointment
  belongs_to :user

  validates :user_id, uniqueness: { scope: :appointment_id }
  validate :same_organization
  validate :not_blocked_by_customer

  private

  def not_blocked_by_customer
    return if appointment.blank? || user_id.blank?

    errors.add(:user, "is blocked by this customer") if appointment.blocked_staff_ids.include?(user_id)
  end

  def same_organization
    return if appointment.blank? || user.blank? || appointment.organization_id == user.organization_id

    errors.add(:user, "must belong to the appointment organization")
  end
end

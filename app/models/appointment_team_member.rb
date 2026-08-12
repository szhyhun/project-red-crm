class AppointmentTeamMember < ApplicationRecord
  belongs_to :appointment
  belongs_to :user

  validates :user_id, uniqueness: { scope: :appointment_id }
  validate :same_organization

  private

  def same_organization
    return if appointment.blank? || user.blank? || appointment.organization_id == user.organization_id

    errors.add(:user, "must belong to the appointment organization")
  end
end

class Appointment < ApplicationRecord
  belongs_to :listing
  belongs_to :organization
  belongs_to :assigned_user, class_name: "User", optional: true

  enum :status, { scheduled: "scheduled", confirmed: "confirmed", completed: "completed", cancelled: "cancelled" }, validate: true

  validates :starts_at, :ends_at, presence: true
  validate :ends_after_start
  validate :assigned_user_belongs_to_organization

  private

  def ends_after_start
    return if starts_at.blank? || ends_at.blank? || ends_at > starts_at

    errors.add(:ends_at, "must be after starts_at")
  end

  def assigned_user_belongs_to_organization
    return if assigned_user.blank? || assigned_user.organization_id == organization_id

    errors.add(:assigned_user, "must belong to the same organization")
  end
end

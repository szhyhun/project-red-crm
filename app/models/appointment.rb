class Appointment < ApplicationRecord
  belongs_to :listing
  belongs_to :organization
  belongs_to :order, optional: true
  belongs_to :assigned_user, class_name: "User", optional: true
  has_many :appointment_team_members, dependent: :destroy
  has_many :team_members, through: :appointment_team_members, source: :user
  has_many :appointment_events, dependent: :destroy
  has_many :appointment_items, dependent: :destroy

  enum :status, {
    scheduled: "scheduled", confirmed: "confirmed", postponed: "postponed",
    completed: "completed", cancelled: "cancelled"
  }, validate: true
  enum :request_status, {
    not_requested: "not_requested", requested: "requested", approved: "approved", declined: "declined"
  }, validate: true

  validates :starts_at, :ends_at, presence: true
  validate :ends_after_start
  validate :assigned_user_belongs_to_organization
  validate :assigned_user_is_available
  validate :order_belongs_to_listing
  before_save :stamp_completion

  private

  def ends_after_start
    return if starts_at.blank? || ends_at.blank? || ends_at > starts_at

    errors.add(:ends_at, "must be after starts_at")
  end

  def assigned_user_belongs_to_organization
    return if assigned_user.blank? || assigned_user.organization_id == organization_id

    errors.add(:assigned_user, "must belong to the same organization")
  end

  def assigned_user_is_available
    return if assigned_user_id.blank? || starts_at.blank? || ends_at.blank? || cancelled?

    conflict = self.class.where(organization_id:, assigned_user_id:)
      .where.not(status: :cancelled)
      .where("starts_at < ? AND ends_at > ?", ends_at, starts_at)
    conflict = conflict.where.not(id:) if persisted?
    errors.add(:assigned_user, "already has an appointment during this time") if conflict.exists?
  end

  def order_belongs_to_listing
    return if order.blank? || order.listing_id == listing_id

    errors.add(:order, "must belong to this listing")
  end

  def stamp_completion
    self.completed_at ||= Time.current if completed?
  end
end

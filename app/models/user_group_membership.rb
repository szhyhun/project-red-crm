class UserGroupMembership < ApplicationRecord
  belongs_to :user_group
  belongs_to :user

  validates :user_id, uniqueness: { scope: :user_group_id }
  validate :user_belongs_to_group_organization

  private

  def user_belongs_to_group_organization
    return if user.blank? || user_group.blank?
    return if user.organization_id == user_group.organization_id

    errors.add(:user, "must belong to the same organization")
  end
end

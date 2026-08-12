class SavedListingView < ApplicationRecord
  belongs_to :organization
  belongs_to :user

  enum :access, { personal: "personal", team: "team" }, validate: true

  validates :name, presence: true, uniqueness: { scope: %i[organization_id user_id] }
  validate :user_belongs_to_organization

  scope :visible_to, ->(user) { where(user: user).or(where(access: :team)) }

  private

  def user_belongs_to_organization
    return if user.blank? || user.organization_id == organization_id

    errors.add(:user, "must belong to the same organization")
  end
end

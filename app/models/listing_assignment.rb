class ListingAssignment < ApplicationRecord
  belongs_to :listing
  belongs_to :user

  validates :role, inclusion: { in: %w[manager photographer videographer editor] }
  validate :user_belongs_to_listing_organization

  private

  def user_belongs_to_listing_organization
    return if listing.blank? || user.blank? || listing.organization_id == user.organization_id

    errors.add(:user, "must belong to the listing organization")
  end
end

class ListingMembership < ApplicationRecord
  belongs_to :listing
  belongs_to :client_membership

  validates :client_membership_id, uniqueness: { scope: :listing_id }
  validate :membership_is_in_a_team_on_the_listing

  private

  def membership_is_in_a_team_on_the_listing
    return if listing.blank? || client_membership.blank?
    return if client_membership.client_account_id == listing.client_account_id
    return if listing.listing_customers.exists?(client_account_id: client_membership.client_account_id)

    errors.add(:client_membership, "must belong to a team on this listing")
  end
end

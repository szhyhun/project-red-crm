class ListingCustomer < ApplicationRecord
  belongs_to :listing
  belongs_to :client_account

  validates :client_account_id, uniqueness: { scope: :listing_id }
  validate :same_organization

  private

  def same_organization
    return if listing.blank? || client_account.blank? || listing.organization_id == client_account.organization_id

    errors.add(:client_account, "must belong to the listing organization")
  end
end

# Which listings a customer may see. A team's active admins see all of its
# listings, and so do its members unless the team gives members only their
# own: the listings their membership is attached to and the ones they booked.
# Every customer-facing policy that derives access from a listing asks this,
# so the rule lives in one place.
class CustomerListingAccess
  def initialize(user)
    @user = user
  end

  def listings(scope = Listing.all)
    return scope.none if user.internal?

    scope.where(id: accessible_listing_ids)
  end

  def allows?(listing)
    return false if listing.blank? || user.internal?

    Listing.where(id: accessible_listing_ids).exists?(listing.id)
  end

  # Teams whose every listing this person sees.
  def whole_team_account_ids
    @whole_team_account_ids ||= user.active_client_memberships.joins(:client_account).where(
      "client_memberships.role = 'admin' OR client_accounts.member_listing_access = 'all_team_listings'"
    ).pluck(:client_account_id)
  end

  private

  attr_reader :user

  def accessible_listing_ids
    whole_team_ids = whole_team_account_ids
    Listing.where(client_account_id: whole_team_ids)
      .or(Listing.where(id: ListingCustomer.where(client_account_id: whole_team_ids).select(:listing_id)))
      .or(Listing.where(id: ListingMembership.where(client_membership_id: user.active_client_memberships.select(:id)).select(:listing_id)))
      .or(Listing.where(booked_by_id: user.id, client_account_id: user.active_client_memberships.select(:client_account_id)))
      .select(:id)
  end
end

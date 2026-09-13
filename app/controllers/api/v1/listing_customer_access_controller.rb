class Api::V1::ListingCustomerAccessController < Api::V1::BaseController
  # The people of the teams on a listing, and which of them it is given to.
  # Staff and those teams' admins decide; a team's admins see it regardless.
  def show
    listing = policy_scope(Listing).find(params[:listing_id])
    authorize listing, :view?

    render json: serialize(listing)
  end

  def update
    listing = policy_scope(Listing).find(params[:listing_id])
    authorize listing, :view?
    raise Pundit::NotAuthorizedError unless may_share?(listing)

    wanted = Array(params.require(:customer_access).fetch(:membership_ids, [])).compact_blank.map(&:to_i)
    memberships = team_memberships(listing).where(id: wanted)
    return render json: { error: "unknown_membership", details: { base: [ "Choose people from the teams on this listing" ] } }, status: :unprocessable_content if memberships.size != wanted.uniq.size

    ListingMembership.transaction do
      listing.listing_memberships.where.not(client_membership_id: wanted).destroy_all
      memberships.each { |membership| listing.listing_memberships.find_or_create_by!(client_membership: membership) }
    end
    ActivityEvent.create!(organization: listing.organization, actor: current_user, subject: listing,
                          event_type: "listing.customer_access_changed", payload: { membership_ids: wanted })

    render json: serialize(listing.reload)
  end

  private

  def team_account_ids(listing)
    [ listing.client_account_id, *listing.listing_customers.pluck(:client_account_id) ].uniq
  end

  def team_memberships(listing)
    ClientMembership.where(client_account_id: team_account_ids(listing)).where.not(status: :revoked)
  end

  def may_share?(listing)
    return current_user.organization_admin? || current_user.manager? if current_user.internal?

    current_user.active_client_memberships.where(role: :admin, client_account_id: team_account_ids(listing)).exists?
  end

  def serialize(listing)
    attached = listing.listing_memberships.pluck(:client_membership_id)
    {
      customer_access: {
        listing_id: listing.id,
        can_change: may_share?(listing),
        memberships: team_memberships(listing).includes(:user, :client_account).order(:client_account_id, :id).map do |membership|
          membership.slice(:id, :role, :status).merge(
            user: membership.user.slice(:id, :name, :email),
            client_account: membership.client_account.slice(:id, :name, :member_listing_access),
            attached: attached.include?(membership.id),
            booked: listing.booked_by_id == membership.user_id,
            sees_listing: membership.admin? || membership.client_account.member_listing_access == "all_team_listings" ||
              attached.include?(membership.id) || listing.booked_by_id == membership.user_id
          )
        end
      }
    }
  end
end

class OrderPolicy < OrganizationRecordPolicy
  def index?
    true
  end

  def view?
    belongs_to_current_organization? && (user.internal? || customer_can_access?)
  end

  def update?
    belongs_to_current_organization? && user.internal? && super
  end

  class Scope < Scope
    def resolve
      orders = scope.where(organization_id: user.organization_id)
      return orders if user.internal?

      # A team's admins see all its orders; anyone else, the orders they
      # placed and those on listings they can see.
      access = CustomerListingAccess.new(user)
      team_orders = orders.where(client_account_id: user.client_account_ids)
      team_orders.where(client_account_id: access.whole_team_account_ids)
                 .or(team_orders.where(ordered_by_id: user.id))
                 .or(team_orders.where(listing_id: access.listings.select(:id)))
    end
  end

  private

  def customer_can_access?
    return false unless user.client_account_ids.include?(record.client_account_id)

    access = CustomerListingAccess.new(user)
    access.whole_team_account_ids.include?(record.client_account_id) || record.ordered_by_id == user.id || access.allows?(record.listing)
  end
end

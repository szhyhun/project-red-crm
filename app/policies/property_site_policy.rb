class PropertySitePolicy < OrganizationRecordPolicy
  def show?
    belongs_to_current_organization? && (user.internal? || customer_can_access_listing?)
  end

  def create?
    user.organization_admin? || user.manager?
  end

  def update?
    belongs_to_current_organization? && (user.organization_admin? || user.manager?)
  end

  class Scope < Scope
    def resolve
      sites = scope.where(organization_id: user.organization_id)
      return sites if user.internal?

      sites.joins(listing: :listing_customers).where(
        "listings.client_account_id IN (:ids) OR listing_customers.client_account_id IN (:ids)", ids: user.client_account_ids
      ).distinct
    end
  end

  private

  def customer_can_access_listing?
    user.client_account_ids.include?(record.listing.client_account_id) ||
      record.listing.listing_customers.where(client_account_id: user.client_account_ids).exists?
  end
end

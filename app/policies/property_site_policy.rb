class PropertySitePolicy < OrganizationRecordPolicy
  def view?
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

      sites.where(listing_id: CustomerListingAccess.new(user).listings.select(:id))
    end
  end

  private

  def customer_can_access_listing?
    CustomerListingAccess.new(user).allows?(record.listing)
  end
end

class ListingPolicy < OrganizationRecordPolicy
  def index?
    true
  end

  def view?
    belongs_to_current_organization? && (user.internal? || customer_can_access?)
  end

  def create?
    user.organization_admin? || user.manager?
  end

  def update?
    belongs_to_current_organization? && user.internal? && super
  end

  class Scope < Scope
    def resolve
      listings = scope.where(organization_id: user.organization_id)
      return listings if user.internal?

      CustomerListingAccess.new(user).listings(listings)
    end
  end

  private

  def customer_can_access?
    CustomerListingAccess.new(user).allows?(record)
  end
end

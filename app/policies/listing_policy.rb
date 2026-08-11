class ListingPolicy < OrganizationRecordPolicy
  def index?
    true
  end

  def show?
    belongs_to_current_organization? && (user.internal? || user.client_account_ids.include?(record.client_account_id))
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

      listings.where(client_account_id: user.client_account_ids)
    end
  end
end

class PropertySitePolicy < OrganizationRecordPolicy
  def show?
    belongs_to_current_organization? && (user.internal? || user.client_account_ids.include?(record.listing.client_account_id))
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

      sites.joins(:listing).where(listings: { client_account_id: user.client_account_ids })
    end
  end
end

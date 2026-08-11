class ListingPolicy < OrganizationRecordPolicy
  def index?
    true
  end

  def create?
    user.organization_admin? || user.manager?
  end
end

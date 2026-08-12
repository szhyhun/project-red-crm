class SavedListingViewPolicy < OrganizationRecordPolicy
  def index?
    true
  end

  def show?
    belongs_to_current_organization? && (record.team? || record.user_id == user.id)
  end

  def create?
    user.internal?
  end

  def update?
    belongs_to_current_organization? && record.user_id == user.id
  end

  def destroy?
    update?
  end

  class Scope < Scope
    def resolve
      scope.where(organization_id: user.organization_id).visible_to(user)
    end
  end
end

class TagPolicy < OrganizationRecordPolicy
  def index?
    user.internal?
  end

  def view?
    belongs_to_current_organization? && user.internal?
  end

  def destroy?
    update?
  end

  class Scope < Scope
    def resolve
      user.internal? ? scope.where(organization_id: user.organization_id) : scope.none
    end
  end
end

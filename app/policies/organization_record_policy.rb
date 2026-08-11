class OrganizationRecordPolicy < ApplicationPolicy
  def show?
    belongs_to_current_organization?
  end

  def create?
    user.organization_admin? || user.manager?
  end

  def update?
    belongs_to_current_organization? && (user.organization_admin? || user.manager?)
  end

  private

  def belongs_to_current_organization?
    record.organization_id == user.organization_id
  end

  class Scope < Scope
    def resolve
      @scope.where(organization_id: user.organization_id)
    end
  end
end

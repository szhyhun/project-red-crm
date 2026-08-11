class ProductPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    record.organization_id == user.organization_id
  end

  def create?
    user.organization_admin? || user.manager?
  end

  def update?
    record.organization_id == user.organization_id && (user.organization_admin? || user.manager?)
  end

  class Scope < Scope
    def resolve
      @scope.where(organization_id: user.organization_id, active: true)
    end
  end
end

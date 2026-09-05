class UserGroupPolicy < ApplicationPolicy
  def view?
    user.internal? && same_organization?
  end

  def index?
    user.internal?
  end

  def create?
    user.admin?
  end

  def update?
    user.admin? && same_organization?
  end

  def destroy?
    update?
  end

  def manage?
    update?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user.internal?

      scope.where(organization_id: user.organization_id)
    end
  end

  private

  def same_organization?
    record.organization_id == user.organization_id
  end
end

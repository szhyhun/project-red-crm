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
    # Everyone ordering should only be offered what is currently available, but
    # the people who maintain the catalog have to be able to see a retired
    # product to bring it back -- filtering `active` for them would make
    # unchecking "available to order" a one-way door, since `update` resolves the
    # record through this same scope.
    def resolve
      scope = @scope.where(organization_id: user.organization_id)
      return scope if user.organization_admin? || user.manager?

      scope.where(active: true)
    end
  end
end

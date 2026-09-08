class ProductComponentPolicy < ApplicationPolicy
  def index?
    same_organization?
  end

  def view?
    same_organization?
  end

  def create?
    manages_catalog?
  end

  alias_method :update?, :create?
  alias_method :destroy?, :create?

  class Scope < Scope
    def resolve
      scope.joins(:package_product).where(products: { organization_id: user.organization_id })
    end
  end

  private

  def same_organization?
    record.organization_id == user.organization_id
  end

  def manages_catalog?
    same_organization? && (user.organization_admin? || user.manager?)
  end
end

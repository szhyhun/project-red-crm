class CustomerUserPolicy < ApplicationPolicy
  CUSTOMER_ROLES = %w[client_admin client_member].freeze

  # Customer people are a staff concern: a customer manages their own profile
  # through the portal, never someone else's record.
  def index?
    user.internal?
  end

  def view?
    customer_in_organization? && user.internal?
  end

  # Blocking someone from ordering or adjusting a credit balance is a decision
  # about the account relationship, not production work.
  def update?
    view? && (user.organization_admin? || user.platform_owner? || user.manager?)
  end

  def manage?
    update?
  end

  def destroy?
    update?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user.internal?

      scope.where(organization_id: user.organization_id, role: CUSTOMER_ROLES)
    end
  end

  private

  def customer_in_organization?
    record.organization_id == user.organization_id && record.role.in?(CUSTOMER_ROLES)
  end
end

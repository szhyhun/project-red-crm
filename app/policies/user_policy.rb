class UserPolicy < ApplicationPolicy
  def index?
    user.internal?
  end

  def invite?
    user.organization_admin? || user.platform_owner?
  end

  def update?
    invite? && record.organization_id == user.organization_id &&
      record.role.in?(%w[organization_admin manager production_staff])
  end
end

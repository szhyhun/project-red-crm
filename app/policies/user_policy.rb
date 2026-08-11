class UserPolicy < ApplicationPolicy
  def index?
    user.internal?
  end

  def invite?
    user.organization_admin?
  end
end

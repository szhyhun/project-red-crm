class UserPolicy < ApplicationPolicy
  # Roles an administrator may hand out. Platform owners and client users are
  # managed elsewhere, so they never appear in the staff screen.
  MANAGEABLE_ROLES = %w[organization_admin manager production_staff].freeze

  def view?
    same_organization? && (own_record? || user.internal?)
  end

  def index?
    user.internal?
  end

  # The session capability map asks this policy at class level. Keeping the
  # invite permission under the shared `create` capability lets the interface
  # render team-management controls without re-implementing role rules.
  def create?
    invite?
  end

  def invite?
    user.organization_admin? || user.platform_owner?
  end

  # Editing your own name or password is a different permission from deciding
  # what someone may do. Everyone gets the first for their own record; only an
  # administrator gets the second, and only over a role they may hand out.
  def update?
    same_organization? && (own_record? || manage?)
  end

  def manage?
    return invite? if record.is_a?(Class)

    invite? && same_organization? && record.role.in?(MANAGEABLE_ROLES)
  end

  private

  def own_record?
    record.id == user.id
  end

  def same_organization?
    record.organization_id == user.organization_id
  end
end

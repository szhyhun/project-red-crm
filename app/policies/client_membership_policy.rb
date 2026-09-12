class ClientMembershipPolicy < ApplicationPolicy
  def view?
    same_organization? && (user.internal? || own? || account_admin?)
  end

  # Inviting belongs to our staff and to the account's own admins.
  def create?
    same_organization? && (user.organization_admin? || account_admin?)
  end

  # An admin changes anyone's role; a person changes their own landing team and
  # their own notifications.
  def update?
    same_organization? && (user.organization_admin? || account_admin? || own?)
  end

  def destroy?
    same_organization? && (user.organization_admin? || account_admin?)
  end

  def manage?
    same_organization? && (user.organization_admin? || account_admin?)
  end

  class Scope < Scope
    def resolve
      memberships = scope.joins(:client_account).where(client_accounts: { organization_id: user.organization_id })
      return memberships if user.internal?

      # Own memberships stay visible whatever their status: an invitation has to
      # be readable to be accepted.
      memberships.where(client_account_id: user.client_account_ids).or(memberships.where(user_id: user.id))
    end
  end

  private

  def same_organization?
    record.client_account.present? && record.client_account.organization_id == user.organization_id
  end

  def own?
    record.user_id == user.id
  end

  def account_admin?
    return false if user.internal?

    user.client_memberships.active.admin.exists?(client_account_id: record.client_account_id)
  end
end

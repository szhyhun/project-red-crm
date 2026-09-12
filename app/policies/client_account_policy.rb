class ClientAccountPolicy < OrganizationRecordPolicy
  def index?
    true
  end

  def view?
    belongs_to_current_organization? && (user.internal? || user.client_account_ids.include?(record.id))
  end

  # Inviting and removing people belongs to the account's own admins as much as
  # to our staff: a team runs itself.
  def invite?
    belongs_to_current_organization? && (user.organization_admin? || account_admin?)
  end

  alias_method :manage?, :invite?

  class Scope < Scope
    def resolve
      accounts = scope.where(organization_id: user.organization_id)
      return accounts if user.internal?

      accounts.where(id: user.client_account_ids)
    end
  end

  private

  def account_admin?
    return false if user.internal?

    user.client_memberships.active.admin.exists?(client_account_id: record.id)
  end
end

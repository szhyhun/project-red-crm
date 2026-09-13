class ClientAccountPolicy < OrganizationRecordPolicy
  CAPABILITIES = [ *ApplicationPolicy::CAPABILITIES, :configure_billing, :archive, :split, :configure_notifications ].freeze

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

  # Who pays and what customers may read are decisions between us and the
  # team, so the team's own admins cannot make them for themselves.
  def configure_billing?
    belongs_to_current_organization? && user.internal? && user.billing_access?
  end

  # A team's admins decide what their team is emailed about, as our staff can.
  def configure_notifications?
    belongs_to_current_organization? && (user.organization_admin? || user.manager? || account_admin?)
  end

  # Archiving or splitting a team changes where every member's work lands, so
  # it is a staff decision too.
  alias_method :archive?, :configure_billing?
  alias_method :split?, :configure_billing?

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

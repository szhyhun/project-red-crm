class ClientAccountPolicy < OrganizationRecordPolicy
  def index?
    true
  end

  def show?
    belongs_to_current_organization? && (user.internal? || user.client_account_ids.include?(record.id))
  end

  class Scope < Scope
    def resolve
      accounts = scope.where(organization_id: user.organization_id)
      return accounts if user.internal?

      accounts.where(id: user.client_account_ids)
    end
  end
end

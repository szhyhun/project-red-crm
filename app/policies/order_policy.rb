class OrderPolicy < OrganizationRecordPolicy
  def index?
    true
  end

  def show?
    belongs_to_current_organization? && (user.internal? || user.client_account_ids.include?(record.client_account_id))
  end

  def update?
    belongs_to_current_organization? && user.internal? && super
  end

  class Scope < Scope
    def resolve
      orders = scope.where(organization_id: user.organization_id)
      return orders if user.internal?

      orders.where(client_account_id: user.client_account_ids)
    end
  end
end

class InvoicePolicy < OrganizationRecordPolicy
  def index?
    true
  end

  def show?
    belongs_to_current_organization? && (user.internal? || user.client_account_ids.include?(record.client_account_id))
  end

  class Scope < Scope
    def resolve
      invoices = scope.where(organization_id: user.organization_id)
      return invoices if user.internal?

      invoices.where(client_account_id: user.client_account_ids)
    end
  end
end

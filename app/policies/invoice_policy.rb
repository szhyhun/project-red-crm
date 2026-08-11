class InvoicePolicy < OrganizationRecordPolicy
  def index?
    true
  end

  def show?
    belongs_to_current_organization? && (user.internal? || user.client_account_ids.include?(record.client_account_id))
  end

  def update?
    belongs_to_current_organization? && user.internal?
  end

  def pay?
    show? && !record.draft? && !record.void? && record.balance_due_cents.positive?
  end

  class Scope < Scope
    def resolve
      invoices = scope.where(organization_id: user.organization_id)
      return invoices if user.internal?

      invoices.where(client_account_id: user.client_account_ids)
    end
  end
end

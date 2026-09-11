class InvoicePolicy < OrganizationRecordPolicy
  def index?
    billing_staff? || customer?
  end

  # Asked at class level for the session capability map, where there is no
  # invoice yet: the answer is then simply whether this person may see billing.
  def view?
    return index? if record.is_a?(Class)

    belongs_to_current_organization? &&
      (billing_staff? || user.client_account_ids.include?(record.client_account_id))
  end

  def update?
    return billing_staff? if record.is_a?(Class)

    belongs_to_current_organization? && billing_staff?
  end

  def pay?
    view? && !record.draft? && !record.void? && record.balance_due_cents.positive?
  end

  class Scope < Scope
    def resolve
      invoices = scope.where(organization_id: user.organization_id)
      return invoices if user.internal? && user.billing_access?
      return invoices.none if user.internal?

      invoices.where(client_account_id: user.client_account_ids)
    end
  end

  private

  def billing_staff?
    user.internal? && user.billing_access?
  end

  def customer?
    !user.internal?
  end
end

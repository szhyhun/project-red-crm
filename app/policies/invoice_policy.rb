class InvoicePolicy < OrganizationRecordPolicy
  def index?
    billing_staff? || customer?
  end

  # Asked at class level for the session capability map, where there is no
  # invoice yet: the answer is then simply whether this person may see billing.
  def view?
    return index? if record.is_a?(Class)

    belongs_to_current_organization? &&
      (billing_staff? || (user.client_account_ids.include?(record.client_account_id) && billing_visible?))
  end

  def update?
    return billing_staff? if record.is_a?(Class)

    belongs_to_current_organization? && billing_staff?
  end

  def pay?
    view? && !record.draft? && !record.void? && record.balance_due_cents.positive? &&
      (billing_staff? || record.client_account.payable_online_by?(user))
  end

  class Scope < Scope
    def resolve
      invoices = scope.where(organization_id: user.organization_id)
      return invoices if user.internal? && user.billing_access?
      return invoices.none if user.internal?

      visible_account_ids = user.client_accounts.select { |account| account.visible_to?(:billing, user) }.map(&:id)
      invoices.where(client_account_id: visible_account_ids)
    end
  end

  private

  def billing_visible?
    record.client_account.visible_to?(:billing, user)
  end

  def billing_staff?
    user.internal? && user.billing_access?
  end

  def customer?
    !user.internal?
  end
end

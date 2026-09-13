class InvoicePolicy < OrganizationRecordPolicy
  def index?
    billing_staff? || customer?
  end

  # Asked at class level for the session capability map, where there is no
  # invoice yet: the answer is then simply whether this person may see billing.
  def view?
    return index? if record.is_a?(Class)

    belongs_to_current_organization? &&
      (billing_staff? || (user.client_account_ids.include?(record.client_account_id) && billing_visible? && listing_visible?))
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

      accounts = user.client_accounts.select { |account| account.visible_to?(:billing, user) }
      # The team's admins and its billing member see every invoice; anyone else,
      # those for no listing or for a listing they can see.
      whole_team_ids = accounts.select { |account| account.billing_user_id == user.id || CustomerListingAccess.new(user).whole_team_account_ids.include?(account.id) }.map(&:id)
      visible = invoices.where(client_account_id: accounts.map(&:id))
      visible.where(client_account_id: whole_team_ids)
             .or(visible.where(listing_id: nil))
             .or(visible.where(listing_id: CustomerListingAccess.new(user).listings.select(:id)))
    end
  end

  private

  def listing_visible?
    account = record.client_account
    record.listing_id.nil? || account.billing_user_id == user.id ||
      CustomerListingAccess.new(user).whole_team_account_ids.include?(account.id) || CustomerListingAccess.new(user).allows?(record.listing)
  end

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

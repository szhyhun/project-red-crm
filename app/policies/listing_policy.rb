class ListingPolicy < OrganizationRecordPolicy
  def index?
    true
  end

  def show?
    belongs_to_current_organization? && (user.internal? || customer_can_access?)
  end

  def create?
    user.organization_admin? || user.manager?
  end

  def update?
    belongs_to_current_organization? && user.internal? && super
  end

  class Scope < Scope
    def resolve
      listings = scope.where(organization_id: user.organization_id)
      return listings if user.internal?

      listings.left_joins(:listing_customers)
        .where("listings.client_account_id IN (:ids) OR listing_customers.client_account_id IN (:ids)", ids: user.client_account_ids)
        .distinct
    end
  end

  private

  def customer_can_access?
    user.client_account_ids.include?(record.client_account_id) ||
      record.listing_customers.where(client_account_id: user.client_account_ids).exists?
  end
end

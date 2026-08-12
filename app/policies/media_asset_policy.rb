class MediaAssetPolicy < OrganizationRecordPolicy
  def index?
    true
  end

  def show?
    visible_to_user?
  end

  def create?
    user.internal?
  end

  def update?
    belongs_to_current_organization? && user.internal?
  end

  alias_method :destroy?, :update?

  class Scope < Scope
    def resolve
      assets = scope.where(organization_id: user.organization_id)
      return assets if user.internal?

      assets.joins(listing: :listing_customers).where(
        "listings.client_account_id IN (:ids) OR listing_customers.client_account_id IN (:ids)", ids: user.client_account_ids
      ).where(kind: "final", status: "ready", customer_visible: true, hidden: false).distinct
    end
  end

  private

  def visible_to_user?
    return false unless belongs_to_current_organization?
    return true if user.internal?

    record.final? && record.ready? && record.customer_visible? && !record.hidden? && record.listing &&
      (user.client_account_ids.include?(record.listing.client_account_id) ||
       record.listing.listing_customers.where(client_account_id: user.client_account_ids).exists?)
  end
end

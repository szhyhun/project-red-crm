class MediaAssetPolicy < OrganizationRecordPolicy
  def index?
    true
  end

  def view?
    visible_to_user?
  end

  # Seeing a file and taking it away are different permissions: a team that
  # locks downloads until payment still shows its customer the preview.
  def download?
    return false unless view?
    return true if user.internal?

    listing = record.listing
    !listing&.client_account&.downloads_locked_for?(listing)
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

      assets.left_joins(listing: :listing_customers).where(
        "listings.client_account_id IN (:ids) OR listing_customers.client_account_id IN (:ids)", ids: user.client_account_ids
      ).where(kind: "final", status: "ready", customer_visible: true, hidden: false, superseded_by_id: nil).distinct
    end
  end

  private

  def visible_to_user?
    return false unless belongs_to_current_organization?
    return true if user.internal?

    record.final? && record.ready? && record.customer_visible? && !record.hidden? && record.listing &&
      record.superseded_by_id.nil? &&
      (user.client_account_ids.include?(record.listing.client_account_id) ||
       record.listing.listing_customers.where(client_account_id: user.client_account_ids).exists?)
  end
end

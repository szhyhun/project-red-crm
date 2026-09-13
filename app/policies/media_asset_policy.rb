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

      assets.where(listing_id: CustomerListingAccess.new(user).listings.select(:id))
            .where(kind: "final", status: "ready", customer_visible: true, hidden: false, superseded_by_id: nil)
    end
  end

  private

  def visible_to_user?
    return false unless belongs_to_current_organization?
    return true if user.internal?

    record.final? && record.ready? && record.customer_visible? && !record.hidden? && record.listing &&
      record.superseded_by_id.nil? &&
      CustomerListingAccess.new(user).allows?(record.listing)
  end
end

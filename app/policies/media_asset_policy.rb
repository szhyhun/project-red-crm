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

  class Scope < Scope
    def resolve
      assets = scope.where(organization_id: user.organization_id)
      return assets if user.internal?

      assets.joins(:listing).where(
        listing: { client_account_id: user.client_account_ids },
        kind: "final",
        status: "ready"
      )
    end
  end

  private

  def visible_to_user?
    return false unless belongs_to_current_organization?
    return true if user.internal?

    record.final? && record.ready? && record.listing && user.client_account_ids.include?(record.listing.client_account_id)
  end
end

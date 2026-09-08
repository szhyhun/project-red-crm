class OrderDeliverablePolicy < OrganizationRecordPolicy
  def index?
    visible_to_user?
  end

  def view?
    visible_to_user?
  end

  def update?
    user.internal? && record.organization_id == user.organization_id
  end

  alias_method :create?, :update?
  alias_method :destroy?, :update?

  class Scope < Scope
    def resolve
      deliverables = scope.where(organization_id: user.organization_id)
      return deliverables if user.internal?

      deliverables.where(listing_id: ListingPolicy::Scope.new(user, Listing).resolve.select(:id))
                  .where(cancelled_at: nil)
    end
  end

  private

  def visible_to_user?
    return false unless record.organization_id == user.organization_id
    return true if user.internal?

    record.cancelled_at.blank? && record.listing.present? && ListingPolicy.new(user, record.listing).view?
  end
end

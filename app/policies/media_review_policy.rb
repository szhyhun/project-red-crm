class MediaReviewPolicy < OrganizationRecordPolicy
  def view?
    record_belongs_to_organization? && (user.internal? || customer_can_access?)
  end

  def create?
    record_belongs_to_organization? && !user.internal? && customer_can_access?
  end

  def update?
    create? && record.open?
  end

  def submit?
    update?
  end

  def manage?
    record_belongs_to_organization? && user.internal?
  end

  class Scope < Scope
    def resolve
      reviews = scope.where(organization_id: user.organization_id)
      return reviews if user.internal?

      reviews.where(client_account_id: user.client_account_ids)
             .where(listing_id: ListingPolicy::Scope.new(user, Listing).resolve.select(:id))
    end
  end

  private

  def record_belongs_to_organization?
    record.organization_id == user.organization_id
  end

  def customer_can_access?
    return false unless record.listing.present? && record.client_account.present?
    return false unless user.client_account_ids.include?(record.client_account_id)

    record.listing.client_account_id == record.client_account_id ||
      record.listing.listing_customers.exists?(client_account_id: record.client_account_id)
  end
end

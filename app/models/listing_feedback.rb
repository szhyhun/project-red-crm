class ListingFeedback < ApplicationRecord
  belongs_to :organization
  belongs_to :listing
  belongs_to :client_account
  belongs_to :order, optional: true

  enum :follow_up_status, { no_follow_up: "none", needed: "needed", resolved: "resolved" }, prefix: true, validate: true

  validates :delivery_rating, :service_rating, :media_rating,
            numericality: { in: 1..4 }, allow_nil: true
  validate :records_belong_to_organization
  validate :client_matches_listing

  private

  def records_belong_to_organization
    errors.add(:listing, "must belong to the same organization") if listing.present? && listing.organization_id != organization_id
    errors.add(:client_account, "must belong to the same organization") if client_account.present? && client_account.organization_id != organization_id
    errors.add(:order, "must belong to the same organization") if order.present? && order.organization_id != organization_id
  end

  def client_matches_listing
    return if listing.blank? || client_account.blank? || listing.customer_accounts.where(id: client_account_id).exists?

    errors.add(:client_account, "must match the listing customer")
  end
end

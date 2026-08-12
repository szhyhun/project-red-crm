class ListingNote < ApplicationRecord
  belongs_to :organization
  belongs_to :listing
  belongs_to :author, class_name: "User"

  enum :note_type, { listing: "listing", customer: "customer" }, validate: true
  enum :body_format, { plain: "plain", html: "html" }, validate: true

  validates :body, presence: true
  validate :records_belong_to_organization

  private

  def records_belong_to_organization
    errors.add(:listing, "must belong to the same organization") if listing.present? && listing.organization_id != organization_id
    errors.add(:author, "must belong to the same organization") if author.present? && author.organization_id != organization_id
  end
end

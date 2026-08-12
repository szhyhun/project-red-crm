class PropertySite < ApplicationRecord
  belongs_to :organization
  belongs_to :listing

  enum :status, { draft: "draft", published: "published", archived: "archived" }, validate: true
  enum :site_kind, { branded: "branded", unbranded: "unbranded" }, validate: true

  validates :slug, presence: true
  validate :listing_belongs_to_organization

  private

  def listing_belongs_to_organization
    return if listing.blank? || listing.organization_id == organization_id

    errors.add(:listing, "must belong to the same organization")
  end
end

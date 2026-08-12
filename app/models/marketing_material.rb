class MarketingMaterial < ApplicationRecord
  belongs_to :organization
  belongs_to :listing
  belongs_to :created_by, class_name: "User", optional: true

  enum :status, { draft: "draft", ready: "ready", archived: "archived" }, validate: true
  enum :material_type, { flyer: "flyer", social_post: "social_post", brochure: "brochure", email: "email" }, validate: true

  validates :title, presence: true
  validate :listing_belongs_to_organization

  private

  def listing_belongs_to_organization
    errors.add(:listing, "must belong to the same organization") if listing && listing.organization_id != organization_id
  end
end

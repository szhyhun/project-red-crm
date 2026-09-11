class MediaAsset < ApplicationRecord
  belongs_to :organization
  belongs_to :listing, optional: true
  belongs_to :uploaded_by, class_name: "User", optional: true
  belongs_to :order, optional: true
  belongs_to :order_item, optional: true
  belongs_to :media_group, optional: true
  belongs_to :order_deliverable, optional: true
  belongs_to :superseded_by, class_name: "MediaAsset", optional: true
  has_many :media_review_assets, dependent: :restrict_with_error
  has_many :media_reviews, through: :media_review_assets
  has_many :superseded_assets, class_name: "MediaAsset", foreign_key: :superseded_by_id, dependent: :nullify

  enum :kind, { final: "final", raw: "raw", marketing: "marketing" }, validate: true
  enum :status, { pending: "pending", processing: "processing", ready: "ready", failed: "failed" }, validate: true

  scope :current_version, -> { where(superseded_by_id: nil) }

  CATEGORIES = %w[images videos floor_plans tours files].freeze
  STORAGE_CONTENT_TYPES = %r{
    \A(?:
      image/(?!svg\+xml(?:;|$))[^\s;]+|
      video/[^\s;]+|
      audio/[^\s;]+|
      application/(?:pdf|zip|gzip|msword|vnd\.openxmlformats-officedocument\.[^\s;]+|vnd\.ms-excel[^\s;]*|vnd\.ms-powerpoint[^\s;]*)|
      text/(?:plain|csv|markdown)
    )\z
  }ix
  UNSAFE_INLINE_CONTENT_TYPES = %w[image/svg+xml text/html application/xhtml+xml].freeze

  validates :filename, :content_type, presence: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :position, numericality: { greater_than_or_equal_to: 0 }
  validates :source_url, format: { with: %r{\Ahttps?://\S+\z}, allow_blank: true }

  def self.safe_storage_content_type?(value)
    value.to_s.match?(STORAGE_CONTENT_TYPES)
  end

  def self.safe_inline_content_type?(value)
    PrivateAttachmentContentType.safe_inline?(value)
  end

  def external?
    source_url.present?
  end

  def current_version?
    superseded_by_id.nil?
  end

  # Only the upload endpoint derived a category from the file; assets registered
  # or linked without one fell to the column default and landed in "files",
  # which is how a listing ends up with 51 JPEGs that the images section cannot
  # see. An image filed under "files" is a mistake far more often than intent.
  before_validation :derive_category_from_content_type, on: :create

  validate :storage_source_present
  validate :related_records_belong_to_organization
  validate :order_deliverable_is_immutable

  private

  def derive_category_from_content_type
    return unless category.blank? || category == "files"

    self.category = if content_type.to_s.start_with?("image/")
                      "images"
    elsif content_type.to_s.start_with?("video/")
                      "videos"
    else
                      category.presence || "files"
    end
  end

  def storage_source_present
    errors.add(:base, "a storage key or source URL is required") if storage_key.blank? && source_url.blank?
  end

  def related_records_belong_to_organization
    errors.add(:order, "must belong to the same organization") if order.present? && order.organization_id != organization_id
    errors.add(:order_item, "must belong to the selected order") if order_item.present? && order_item.order_id != order_id
    errors.add(:order_item, "must belong to the same organization") if order_item.present? && order_item.order.organization_id != organization_id
    errors.add(:listing, "must match the order listing") if order.present? && order.listing_id.present? && listing_id.present? && order.listing_id != listing_id
    if order_deliverable.present?
      errors.add(:order_deliverable, "must belong to the same organization") if order_deliverable.organization_id != organization_id
      errors.add(:listing, "must match the deliverable listing") if order_deliverable.listing_id.present? && listing_id.present? && order_deliverable.listing_id != listing_id
      errors.add(:order, "must match the deliverable order") if order_id.present? && order_deliverable.order_id != order_id
      errors.add(:order_item, "must match the deliverable item") if order_item_id.present? && order_deliverable.order_item_id != order_item_id
    end
  end

  # A deliverable is the production lineage for an asset. Reassigning an
  # existing asset silently would make the old task and customer history point
  # at the wrong file, so a replacement must create a new version instead.
  def order_deliverable_is_immutable
    return unless persisted? && will_save_change_to_order_deliverable_id?
    return unless order_deliverable_id_was.present? && order_deliverable_id_was != order_deliverable_id

    errors.add(:order_deliverable, "cannot be changed once assigned")
  end
end

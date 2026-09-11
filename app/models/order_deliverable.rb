class OrderDeliverable < ApplicationRecord
  STATUSES = %w[not_started in_progress in_review delivered].freeze

  belongs_to :organization
  belongs_to :listing, optional: true
  belongs_to :order
  belongs_to :order_item
  belongs_to :product_component, optional: true
  belongs_to :service_product, class_name: "Product"
  has_many :media_assets, dependent: :nullify
  has_many :workflow_task_deliverables, dependent: :destroy
  has_many :workflow_tasks, through: :workflow_task_deliverables
  has_many :activity_events, as: :subject, dependent: :destroy
  # Message references belong to messages, not directly to the deliverable.
  # Keeping this as a through association avoids querying the nonexistent
  # `message_media_references.order_deliverable_id` column when work is removed.
  has_many :messages, dependent: :nullify
  has_many :message_media_references, through: :messages
  has_many :media_review_deliverables, dependent: :destroy
  has_many :media_reviews, through: :media_review_deliverables
  has_many :media_review_assets, dependent: :nullify
  has_many :media_review_threads, dependent: :nullify

  enum :status, STATUSES.index_by(&:itself), validate: true

  validates :title, :deliverable_type, :materialization_key, presence: true
  validates :sla_days, :delivery_version, :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :scope_sqft_min, :scope_sqft_max, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :materialization_key, uniqueness: true
  validate :related_records_belong_to_organization
  validate :scope_is_valid
  validate :order_item_matches_product_lineage
  before_update :advance_delivery_version, if: :new_delivery_version?
  # An open draft was written about the files this delivery just replaced.
  after_update :outdate_open_reviews, if: :saved_change_to_delivery_version?

  scope :active, -> { where(cancelled_at: nil) }
  scope :ordered, -> { order(:position, :id) }

  def customer_visible_assets
    media_assets.current_version.final.ready.where(customer_visible: true, hidden: false)
      .order(:position, :created_at, :id)
  end

  def customer_status
    status
  end

  private

  def related_records_belong_to_organization
    errors.add(:order, "must belong to the same organization") if order.present? && order.organization_id != organization_id
    errors.add(:order_item, "must belong to the order") if order_item.present? && order_item.order_id != order_id
    errors.add(:listing, "must belong to the same organization") if listing.present? && listing.organization_id != organization_id
    if listing.present? && order.present? && order.listing_id.present? && listing_id != order.listing_id
      errors.add(:listing, "must match the order listing")
    end
    errors.add(:service_product, "must belong to the same organization") if service_product.present? && service_product.organization_id != organization_id
    if product_component.present? && (product_component.organization_id != organization_id || product_component.service_product_id != service_product_id)
      errors.add(:product_component, "must belong to the selected service and organization")
    end
  end

  def scope_is_valid
    return unless scope_sqft_min.present? && scope_sqft_max.present?
    return if scope_sqft_max >= scope_sqft_min

    errors.add(:scope_sqft_max, "must be greater than or equal to the minimum square footage")
  end

  def order_item_matches_product_lineage
    return if order_item.blank? || service_product.blank? || order_item.product_id.blank?

    if product_component.present?
      return if order_item.product_id == product_component.package_product_id

      errors.add(:order_item, "must belong to the package product")
    elsif order_item.product&.package? && metadata.to_h.stringify_keys["package_component_id"].present?
      # A component can be removed or repointed after checkout but before
      # approval. The order-line snapshot keeps that included service
      # materializable even when the live component row no longer matches it.
    elsif order_item.product_id != service_product_id
      errors.add(:order_item, "must reference the standalone service product")
    end
  end

  def new_delivery_version?
    status_change = changes_to_save["status"]
    status_change.present? && status_change.first != "delivered" && status_change.last == "delivered" &&
      !will_save_change_to_delivery_version?
  end

  def advance_delivery_version
    self.delivery_version = delivery_version.to_i + 1
  end

  def outdate_open_reviews
    media_reviews.open.find_each(&:mark_outdated!)
  end
end

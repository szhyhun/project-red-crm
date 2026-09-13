class Listing < ApplicationRecord
  belongs_to :organization
  belongs_to :client_account
  belongs_to :booked_by, class_name: "User", optional: true
  has_many :listing_customers, dependent: :destroy
  has_many :listing_memberships, dependent: :destroy
  has_many :customer_accounts, through: :listing_customers, source: :client_account
  has_many :listing_custom_fields, -> { order(:position, :id) }, dependent: :destroy
  has_many :orders, dependent: :nullify
  has_many :order_deliverables, dependent: :nullify
  has_many :appointments, dependent: :destroy
  has_many :listing_assignments, dependent: :destroy
  has_many :assigned_users, through: :listing_assignments, source: :user
  has_many :workflow_tasks, dependent: :destroy
  has_many :media_assets, dependent: :nullify
  has_many :media_groups, dependent: :destroy
  has_many :listing_notes, dependent: :destroy
  has_many :payroll_items, dependent: :destroy
  has_many :listing_feedbacks, dependent: :destroy
  has_many :activity_events, as: :subject, dependent: :destroy
  has_one :property_site, dependent: :destroy
  has_many :marketing_materials, dependent: :destroy
  has_many :invoices, dependent: :nullify
  has_many :conversations, dependent: :nullify
  has_many :media_reviews, dependent: :destroy

  enum :status, {
    draft: "draft", quoted: "quoted", booked: "booked", in_production: "in_production",
    review: "review", delivered: "delivered", cancelled: "cancelled"
  }, validate: true
  enum :delivery_status, { undelivered: "undelivered", delivered: "delivered" }, prefix: :delivery, validate: true
  enum :property_status, {
    coming_soon: "coming_soon", for_sale: "for_sale", for_lease: "for_lease",
    pending_sale: "pending_sale", pending_lease: "pending_lease", for_rent: "for_rent",
    sold: "sold", off_market: "off_market"
  }, validate: true

  validates :address_line_1, presence: true
  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :lot_acres, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :year_built, numericality: { only_integer: true, greater_than: 1_700, less_than_or_equal_to: ->(_listing) { Time.current.year + 2 } }, allow_nil: true
  validate :client_account_belongs_to_organization
  validate :client_account_is_not_archived, on: :create
  after_save :sync_primary_listing_customer

  def address
    [ address_line_1, address_line_2, city, province, postal_code ].compact_blank.join(", ")
  end

  private

  def client_account_belongs_to_organization
    return if client_account.blank? || organization_id == client_account.organization_id

    errors.add(:client_account, "must belong to the same organization")
  end

  def sync_primary_listing_customer
    listing_customers.where.not(client_account_id:).update_all(primary: false)
    listing_customers.find_or_create_by!(client_account_id:) do |customer|
      customer.primary = true
      customer.marketing_visible = true
    end.update!(primary: true)
  end

  # An archived team keeps its history but takes no new work.
  def client_account_is_not_archived
    errors.add(:client_account, "is archived") if client_account&.archived?
  end
end

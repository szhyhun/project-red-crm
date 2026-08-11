class Listing < ApplicationRecord
  belongs_to :organization
  belongs_to :client_account
  has_many :orders, dependent: :nullify
  has_many :appointments, dependent: :destroy
  has_many :listing_assignments, dependent: :destroy
  has_many :assigned_users, through: :listing_assignments, source: :user
  has_many :workflow_tasks, dependent: :destroy
  has_many :media_assets, dependent: :nullify
  has_many :activity_events, as: :subject, dependent: :destroy
  has_one :property_site, dependent: :destroy
  has_many :invoices, dependent: :nullify
  has_many :conversations, dependent: :nullify

  enum :status, {
    draft: "draft", quoted: "quoted", booked: "booked", in_production: "in_production",
    review: "review", delivered: "delivered", cancelled: "cancelled"
  }, validate: true

  validates :address_line_1, presence: true
  validate :client_account_belongs_to_organization

  def address
    [address_line_1, address_line_2, city, province, postal_code].compact_blank.join(", ")
  end

  private

  def client_account_belongs_to_organization
    return if client_account.blank? || organization_id == client_account.organization_id

    errors.add(:client_account, "must belong to the same organization")
  end
end

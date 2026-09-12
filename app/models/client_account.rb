class ClientAccount < ApplicationRecord
  has_many :listing_customers, dependent: :destroy
  has_many :customer_listings, through: :listing_customers, source: :listing
  belongs_to :organization
  has_many :client_memberships, dependent: :destroy
  has_many :customer_team_memberships, dependent: :destroy
  has_many :customer_teams, through: :customer_team_memberships
  has_many :pricing_plans, dependent: :destroy
  has_many :users, through: :client_memberships
  has_many :listings, dependent: :restrict_with_error
  has_many :orders, dependent: :restrict_with_error
  has_many :invoices, dependent: :restrict_with_error
  has_many :conversations, dependent: :restrict_with_error
  has_many :listing_feedbacks, dependent: :restrict_with_error
  has_many :media_reviews, dependent: :destroy

  enum :kind, { agent: "agent", team: "team", brokerage: "brokerage" }, validate: true

  validates :name, presence: true
  validates :affiliate_id, uniqueness: { scope: :organization_id, case_sensitive: false }, allow_blank: true

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  before_validation :normalize_affiliate_id

  def archived?
    archived_at.present?
  end

  def active_admins
    client_memberships.active.admin
  end

  # The team's own setting, applied to one listing: files stay unavailable while
  # that listing still owes money. Staff are never gated by it.
  def downloads_locked_for?(listing)
    return false unless lock_downloads_before_payment?
    return false if listing.blank?

    listing.orders.sum { |order| order.balance_due_cents.to_i }.positive?
  end

  private

  def normalize_affiliate_id
    self.affiliate_id = affiliate_id.strip.presence if affiliate_id.is_a?(String)
  end
end

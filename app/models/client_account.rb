class ClientAccount < ApplicationRecord
  has_many :listing_customers, dependent: :destroy
  has_many :customer_listings, through: :listing_customers, source: :listing
  belongs_to :organization
  belongs_to :billing_user, class_name: "User", optional: true
  has_many :client_memberships, dependent: :destroy
  has_many :pricing_plans, dependent: :destroy
  has_many :users, through: :client_memberships
  has_many :listings, dependent: :restrict_with_error
  has_many :orders, dependent: :restrict_with_error
  has_many :invoices, dependent: :restrict_with_error
  has_many :conversations, dependent: :restrict_with_error
  has_many :listing_feedbacks, dependent: :restrict_with_error
  has_many :media_reviews, dependent: :destroy

  VISIBILITY_BLOCKS = %w[billing pricing downloads marketing_templates].freeze
  VISIBILITIES = %w[hidden admins everyone].freeze
  NOTIFICATION_EVENTS = %w[team_invitation order_confirmation listing_delivered payment_required payment_overdue
                           payment_received feedback_requested appointment_scheduled appointment_reminder].freeze
  NOTIFICATION_CHANNELS = %w[email sms push].freeze

  enum :kind, { agent: "agent", team: "team", brokerage: "brokerage" }, validate: true

  validates :name, presence: true
  validates :affiliate_id, uniqueness: { scope: :organization_id, case_sensitive: false }, allow_blank: true
  VISIBILITY_BLOCKS.each { |block| validates :"#{block}_visibility", inclusion: { in: VISIBILITIES } }
  validate :notification_preferences_are_known
  validate :billing_user_is_an_active_admin, if: -> { billing_user_id.present? && will_save_change_to_billing_user_id? }

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

  def notify?(event, channel = "email")
    notification_preferences.dig(event.to_s, channel.to_s) != false
  end

  # Whether a customer may read one of the team's settings blocks. The billing
  # member always sees billing, since the bill is theirs.
  def visible_to?(block, user)
    return true if user.internal?
    return true if block.to_s == "billing" && billing_user_id == user.id

    membership = client_memberships.active.find_by(user:)
    return false if membership.blank?

    case public_send(:"#{block}_visibility")
    when "everyone" then true
    when "admins" then membership.admin?
    else false
    end
  end

  # With a billing member, nobody else in the team is asked to pay; a team that
  # settles outside the system is not asked to pay online at all.
  def payable_online_by?(user)
    return false if billing_pays_externally?

    billing_user_id.nil? || billing_user_id == user.id
  end

  private

  def notification_preferences_are_known
    valid = notification_preferences.is_a?(Hash) && notification_preferences.all? do |event, channels|
      event.in?(NOTIFICATION_EVENTS) && channels.is_a?(Hash) &&
        channels.all? { |channel, enabled| channel.in?(NOTIFICATION_CHANNELS) && enabled.in?([ true, false ]) }
    end
    errors.add(:notification_preferences, "must switch known events and channels on or off") unless valid
  end

  def billing_user_is_an_active_admin
    return if client_memberships.active.admin.exists?(user_id: billing_user_id)

    errors.add(:billing_user, "must be an active admin of this team")
  end

  def normalize_affiliate_id
    self.affiliate_id = affiliate_id.strip.presence if affiliate_id.is_a?(String)
  end
end

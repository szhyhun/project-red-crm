class PricingPlan < ApplicationRecord
  belongs_to :organization
  belongs_to :client_account, optional: true
  belongs_to :customer_team, optional: true
  belongs_to :user, optional: true
  belongs_to :coupon, optional: true
  has_many :pricing_plan_prices, dependent: :destroy

  accepts_nested_attributes_for :pricing_plan_prices, allow_destroy: true

  scope :active, -> { where(active: true) }

  validates :name, presence: true
  validates :priority, numericality: { only_integer: true }
  validate :exactly_one_owner
  validate :related_records_belong_to_organization

  private

  # A plan belongs to one person, one team, or one grouping -- never to two of
  # them, because then nothing could say which price was promised.
  def exactly_one_owner
    owners = [ client_account_id, customer_team_id, user_id ].count(&:present?)
    return if owners == 1

    errors.add(:base, "must belong to exactly one client account, customer team, or person")
  end

  def related_records_belong_to_organization
    errors.add(:client_account, "must belong to the same organization") if client_account.present? && client_account.organization_id != organization_id
    errors.add(:customer_team, "must belong to the same organization") if customer_team.present? && customer_team.organization_id != organization_id
    errors.add(:user, "must belong to the same organization") if user.present? && user.organization_id != organization_id
    errors.add(:coupon, "must belong to the same organization") if coupon.present? && coupon.organization_id != organization_id
  end
end

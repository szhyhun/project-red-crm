class PricingPlan < ApplicationRecord
  belongs_to :organization
  belongs_to :client_account, optional: true
  belongs_to :customer_team, optional: true
  belongs_to :coupon, optional: true
  has_many :pricing_plan_prices, dependent: :destroy

  accepts_nested_attributes_for :pricing_plan_prices, allow_destroy: true

  scope :active, -> { where(active: true) }

  validates :name, presence: true
  validates :priority, numericality: { only_integer: true }
  validate :exactly_one_owner
  validate :related_records_belong_to_organization

  private

  def exactly_one_owner
    return if client_account_id.present? ^ customer_team_id.present?

    errors.add(:base, "must belong to exactly one client account or customer team")
  end

  def related_records_belong_to_organization
    errors.add(:client_account, "must belong to the same organization") if client_account.present? && client_account.organization_id != organization_id
    errors.add(:customer_team, "must belong to the same organization") if customer_team.present? && customer_team.organization_id != organization_id
    errors.add(:coupon, "must belong to the same organization") if coupon.present? && coupon.organization_id != organization_id
  end
end

class Coupon < ApplicationRecord
  belongs_to :organization
  has_many :pricing_plans, dependent: :nullify

  enum :discount_type, { fixed: "fixed", percentage: "percentage" }, validate: true

  scope :redeemable, -> {
    now = Time.current
    where(active: true)
      .where("starts_at IS NULL OR starts_at <= ?", now)
      .where("ends_at IS NULL OR ends_at >= ?", now)
      .where("max_redemptions IS NULL OR redemption_count < max_redemptions")
  }

  validates :code, presence: true, uniqueness: { scope: :organization_id }
  validates :amount_cents, :rate_basis_points, :redemption_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :max_redemptions, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :discount_value_matches_type
  validate :ends_after_start

  before_validation :normalize_code

  def redeemable?(at: Time.current)
    active? && (starts_at.blank? || starts_at <= at) && (ends_at.blank? || ends_at >= at) &&
      (max_redemptions.blank? || redemption_count < max_redemptions)
  end

  private

  def normalize_code
    self.code = code.to_s.strip.upcase
  end

  def discount_value_matches_type
    if fixed?
      errors.add(:amount_cents, "must be greater than zero for a fixed coupon") unless amount_cents.to_i.positive?
    elsif percentage? && !rate_basis_points.to_i.between?(1, 10_000)
      errors.add(:rate_basis_points, "must be between 1 and 10000 for a percentage coupon")
    end
  end

  def ends_after_start
    return if starts_at.blank? || ends_at.blank? || ends_at > starts_at

    errors.add(:ends_at, "must be after starts_at")
  end
end

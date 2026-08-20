class TravelFee < ApplicationRecord
  belongs_to :organization

  enum :fee_type, { flat: "flat", percentage: "percentage", per_km: "per_km" }, validate: true

  validates :name, presence: true
  validates :amount_cents, :rate_basis_points, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :free_within_km, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :fee_value_matches_type

  private

  def fee_value_matches_type
    if percentage? && !rate_basis_points.to_i.between?(1, 10_000)
      errors.add(:rate_basis_points, "must be between 1 and 10000 for a percentage fee")
    elsif !percentage? && !amount_cents.to_i.positive?
      errors.add(:amount_cents, "must be greater than zero")
    end
  end
end

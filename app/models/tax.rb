class Tax < ApplicationRecord
  belongs_to :organization

  enum :scope, { state: "state", county: "county", custom: "custom" }, validate: true

  validates :name, presence: true, uniqueness: { scope: :organization_id, case_sensitive: false }
  validates :rate_basis_points, numericality: { only_integer: true, in: 0..10_000 }

  before_validation :normalize_name

  private

  def normalize_name
    self.name = name.strip if name.is_a?(String)
  end
end

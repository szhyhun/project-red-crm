class CustomerTeam < ApplicationRecord
  belongs_to :organization
  has_many :customer_team_memberships, dependent: :destroy
  has_many :client_accounts, through: :customer_team_memberships
  has_many :pricing_plans, dependent: :destroy

  enum :origin, { native: "native", aryeo: "aryeo" }, validate: true

  validates :name, presence: true, uniqueness: { scope: :organization_id, case_sensitive: false }

  scope :active, -> { where(archived: false) }

  before_validation :normalize_name

  private

  def normalize_name
    self.name = name.strip if name.is_a?(String)
  end
end

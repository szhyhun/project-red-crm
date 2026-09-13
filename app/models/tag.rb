class Tag < ApplicationRecord
  belongs_to :organization
  has_many :client_account_tags, dependent: :destroy
  has_many :client_accounts, through: :client_account_tags

  before_validation { self.name = name.to_s.strip }

  validates :name, presence: true, uniqueness: { scope: :organization_id, case_sensitive: false }
  validates :color, format: { with: /\A#\h{6}\z/, message: "must be a colour like #1f7a4d" }
end

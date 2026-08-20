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

  enum :kind, { agent: "agent", team: "team", brokerage: "brokerage" }, validate: true

  validates :name, presence: true
end

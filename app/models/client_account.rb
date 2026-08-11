class ClientAccount < ApplicationRecord
  belongs_to :organization
  has_many :client_memberships, dependent: :destroy
  has_many :users, through: :client_memberships
  has_many :listings, dependent: :restrict_with_error
  has_many :orders, dependent: :restrict_with_error

  enum :kind, { agent: "agent", team: "team", brokerage: "brokerage" }, validate: true

  validates :name, presence: true
end

class ClientAccount < ApplicationRecord
  belongs_to :organization
  has_many :client_memberships, dependent: :destroy
  has_many :users, through: :client_memberships

  enum :kind, { agent: "agent", team: "team", brokerage: "brokerage" }, validate: true

  validates :name, presence: true
end

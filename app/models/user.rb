class User < ApplicationRecord
  devise :invitable, :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  belongs_to :organization
  has_many :client_memberships, dependent: :destroy
  has_many :client_accounts, through: :client_memberships

  enum :role, {
    platform_owner: "platform_owner",
    organization_admin: "organization_admin",
    manager: "manager",
    production_staff: "production_staff",
    client_admin: "client_admin",
    client_member: "client_member"
  }, validate: true

  enum :status, { active: "active", suspended: "suspended" }, validate: true

  validates :name, presence: true
end
end

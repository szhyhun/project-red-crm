class User < ApplicationRecord
  devise :invitable, :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  belongs_to :organization
  has_many :client_memberships, dependent: :destroy
  has_many :client_accounts, through: :client_memberships
  has_many :assigned_appointments, class_name: "Appointment", foreign_key: :assigned_user_id,
           dependent: :nullify
  has_many :listing_assignments, dependent: :destroy
  has_many :assigned_listings, through: :listing_assignments, source: :listing
  has_many :assigned_workflow_tasks, class_name: "WorkflowTask", foreign_key: :assignee_id,
           dependent: :nullify

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

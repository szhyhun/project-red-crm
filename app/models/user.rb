class User < ApplicationRecord
  devise :invitable, :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  belongs_to :organization
  has_many :client_memberships, dependent: :destroy
  has_many :credit_transactions, dependent: :destroy
  has_many :customer_blocked_staff, foreign_key: :customer_id, dependent: :destroy, inverse_of: :customer
  has_many :blocked_staff, through: :customer_blocked_staff, source: :staff
  has_many :active_client_memberships, -> { where(status: :active) }, class_name: "ClientMembership", inverse_of: :user, dependent: nil
  # Access follows an accepted membership. An invitation grants nothing until it
  # is accepted, and a revoked one grants nothing after, so every policy that
  # asks for `client_account_ids` is answered by the memberships that count.
  has_many :client_accounts, through: :active_client_memberships
  has_many :assigned_appointments, class_name: "Appointment", foreign_key: :assigned_user_id,
    dependent: :nullify
  has_many :appointment_team_members, dependent: :destroy
  has_many :team_appointments, through: :appointment_team_members, source: :appointment
  has_many :listing_assignments, dependent: :destroy
  has_many :assigned_listings, through: :listing_assignments, source: :listing
  has_many :assigned_workflow_tasks, class_name: "WorkflowTask", foreign_key: :assignee_id,
           dependent: :nullify
  has_many :user_group_memberships, dependent: :destroy
  has_many :user_groups, through: :user_group_memberships
  has_many :board_memberships, as: :member, dependent: :destroy
  has_many :conversation_memberships, dependent: :destroy
  has_many :conversations, through: :conversation_memberships
  has_many :saved_listing_views, dependent: :destroy
  has_many :authored_listing_notes, class_name: "ListingNote", foreign_key: :author_id, dependent: :destroy
  has_many :uploaded_board_attachments, class_name: "BoardAttachment", foreign_key: :uploaded_by_id, dependent: :nullify
  has_many :uploaded_conversation_attachments, class_name: "ConversationAttachment", foreign_key: :uploaded_by_id, dependent: :nullify
  has_many :created_payroll_items, class_name: "PayrollItem", foreign_key: :created_by_id, dependent: :restrict_with_error
  has_many :payroll_items, class_name: "PayrollItem", foreign_key: :team_member_id, dependent: :nullify
  has_one :listing_view_preference, dependent: :destroy
  has_many :created_media_reviews, class_name: "MediaReview", foreign_key: :created_by_id, dependent: :restrict_with_error
  has_many :submitted_media_reviews, class_name: "MediaReview", foreign_key: :submitted_by_id, dependent: :nullify
  has_many :created_media_review_threads, class_name: "MediaReviewThread", foreign_key: :created_by_id, dependent: :restrict_with_error
  has_many :resolved_media_review_threads, class_name: "MediaReviewThread", foreign_key: :resolved_by_id, dependent: :nullify
  has_many :media_review_comments, foreign_key: :author_id, dependent: :restrict_with_error

  # Setting a password on an invitation is the acceptance: the memberships that
  # invitation was sent for become real at the same moment.
  after_invitation_accepted :activate_invited_memberships

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

  def internal?
    !client_admin? && !client_member?
  end

  def admin?
    organization_admin? || platform_owner?
  end

  # Staff who handle money: they create, send and chase invoices. A production
  # specialist works on an order but not on what it costs, so customer billing
  # is not theirs to read.
  def billing_access?
    organization_admin? || platform_owner? || manager?
  end

  def activate_invited_memberships
    client_memberships.invited.find_each(&:accept!)
  end
end

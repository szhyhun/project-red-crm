class ClientMembership < ApplicationRecord
  STATUSES = %w[invited active revoked archived].freeze

  belongs_to :client_account
  belongs_to :user
  has_many :activity_events, as: :subject, dependent: :destroy

  enum :role, { admin: "admin", member: "member" }, validate: true
  enum :status, STATUSES.index_by(&:itself), validate: true

  validate :same_organization
  validate :account_keeps_an_admin
  validate :billing_member_stays_an_admin

  # The partial unique index allows one landing team per person; clearing the
  # others first is what keeps a switch from colliding with it.
  before_save :clear_other_defaults, if: -> { is_default? && will_save_change_to_is_default? }
  after_update :hand_default_on, if: :saved_change_to_status?

  def accept!(at: Time.current)
    transaction do
      update!(status: :active, invitation_accepted_at: invitation_accepted_at || at)
      make_default! if user.client_memberships.active.where(is_default: true).none?
    end
  end

  def revoke!
    update!(status: :revoked)
  end

  def archive!
    update!(status: :archived)
  end

  def make_default!
    update!(is_default: true)
  end

  private

  def same_organization
    return if client_account.blank? || user.blank? || client_account.organization_id == user.organization_id

    errors.add(:user, "must belong to the client account organization")
  end

  # An account with nobody who may invite, remove or see billing is an account
  # its own people have locked themselves out of.
  def account_keeps_an_admin
    return if client_account.blank? || !persisted?
    return unless will_save_change_to_role? || will_save_change_to_status?
    return if admin? && active?
    return unless role_in_database == "admin" && status_in_database == "active"
    return if client_account.client_memberships.active.admin.where.not(id: id).exists?

    errors.add(:base, "An account must keep at least one active admin")
  end

  # The team's bill has to land on someone who can still see and pay it.
  def billing_member_stays_an_admin
    return if client_account.blank? || !persisted?
    return unless will_save_change_to_role? || will_save_change_to_status?
    return if admin? && active?
    return unless client_account.billing_user_id == user_id

    errors.add(:base, "Choose another billing member before changing this person's access")
  end

  def clear_other_defaults
    user.client_memberships.where(is_default: true).where.not(id: id).update_all(is_default: false, updated_at: Time.current)
  end

  # Losing access should not leave someone with no team to land in.
  def hand_default_on
    return if active?
    return unless is_default?

    successor = user.client_memberships.active.where.not(id: id).order(:created_at, :id).first
    update_columns(is_default: false, updated_at: Time.current)
    successor&.update_columns(is_default: true, updated_at: Time.current)
  end
end

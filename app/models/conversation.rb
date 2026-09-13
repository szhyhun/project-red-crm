class Conversation < ApplicationRecord
  RETENTION_PERIOD_DAYS = {
    "two_months" => 60,
    "six_months" => 180,
    "one_year" => 365
  }.freeze

  belongs_to :organization
  belongs_to :listing, optional: true
  belongs_to :client_account, optional: true
  has_many :conversation_memberships, dependent: :destroy
  has_many :users, through: :conversation_memberships
  has_many :messages, dependent: :destroy
  has_many :conversation_attachments, dependent: :destroy
  has_many :message_media_references, through: :messages

  def self.account_thread_for(organization:, client_account:, subject: "Client conversation")
    relation = organization.conversations.client.where(client_account: client_account).order(:created_at, :id)
    conversation = relation.first
    return conversation if conversation.present?

    organization.conversations.create!(kind: :client, client_account:, subject:)
  end

  # Who is in a team's chat without being named: its active admins. Every path
  # that opens or posts into a team chat uses this, so the rule lives once.
  def team_admin_user_ids
    return [] unless client? && client_account

    client_account.active_admins.joins(:user).merge(User.active).pluck(:user_id)
  end

  def join_team_admins!
    team_admin_user_ids.each do |user_id|
      conversation_memberships.find_or_create_by!(user_id:) { |membership| membership.role = :participant }
    end
  end

  enum :kind, { internal: "internal", client: "client" }, validate: true
  enum :retention_period, {
    two_months: "two_months",
    six_months: "six_months",
    one_year: "one_year",
    forever: "forever"
  }, default: :two_months, validate: true

  def retention_days
    RETENTION_PERIOD_DAYS[retention_period]
  end

  def retention_cutoff(now = Time.current)
    return if forever?

    now - retention_days.days
  end

  validate :kind_has_valid_scope
  validate :related_records_belong_to_organization

  private

  def kind_has_valid_scope
    errors.add(:client_account, "is required for a customer conversation") if client? && client_account.blank?
    errors.add(:client_account, "is not allowed for an organization conversation") if internal? && client_account.present?
    return if listing.blank? || client_account.blank? || listing.client_account_id == client_account_id

    errors.add(:listing, "must belong to the selected customer account")
  end

  def related_records_belong_to_organization
    errors.add(:listing, "must belong to the same organization") if listing.present? && listing.organization_id != organization_id
    errors.add(:client_account, "must belong to the same organization") if client_account.present? && client_account.organization_id != organization_id
  end
end

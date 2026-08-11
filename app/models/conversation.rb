class Conversation < ApplicationRecord
  belongs_to :organization
  belongs_to :listing, optional: true
  belongs_to :client_account, optional: true
  has_many :conversation_memberships, dependent: :destroy
  has_many :users, through: :conversation_memberships
  has_many :messages, dependent: :destroy

  enum :kind, { internal: "internal", client: "client" }, validate: true

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

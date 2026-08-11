class Conversation < ApplicationRecord
  belongs_to :organization
  belongs_to :listing, optional: true
  belongs_to :client_account, optional: true
  has_many :conversation_memberships, dependent: :destroy
  has_many :users, through: :conversation_memberships
  has_many :messages, dependent: :destroy

  enum :kind, { internal: "internal", client: "client" }, validate: true

  validate :related_records_belong_to_organization

  private

  def related_records_belong_to_organization
    errors.add(:listing, "must belong to the same organization") if listing.present? && listing.organization_id != organization_id
    errors.add(:client_account, "must belong to the same organization") if client_account.present? && client_account.organization_id != organization_id
  end
end

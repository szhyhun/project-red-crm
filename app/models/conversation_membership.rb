class ConversationMembership < ApplicationRecord
  belongs_to :conversation
  belongs_to :user

  enum :role, { participant: "participant", manager: "manager" }, validate: true

  validate :same_organization

  private

  def same_organization
    return if conversation.blank? || user.blank? || conversation.organization_id == user.organization_id

    errors.add(:user, "must belong to the conversation organization")
  end
end

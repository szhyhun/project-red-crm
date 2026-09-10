class ConversationMembership < ApplicationRecord
  belongs_to :conversation
  belongs_to :user

  enum :role, { participant: "participant", manager: "manager" }, validate: true

  before_create :assign_conversation_position

  validate :same_organization

  private

  # Team chat order is a personal sidebar preference. Customer conversations
  # are sorted by their activity, so they deliberately keep the default value.
  def assign_conversation_position
    return unless conversation&.internal?

    self.position = ConversationMembership
      .joins(:conversation)
      .where(user_id:, conversations: { organization_id: conversation.organization_id, kind: Conversation.kinds.fetch("internal") })
      .maximum(:position).to_i + 1
  end

  def same_organization
    return if conversation.blank? || user.blank? || conversation.organization_id == user.organization_id

    errors.add(:user, "must belong to the conversation organization")
  end
end

class ConversationPolicy < OrganizationRecordPolicy
  def index?
    true
  end

  def show?
    visible_to_user?
  end

  def create?
    user.internal?
  end

  def create_message?
    visible_to_user?
  end

  class Scope < Scope
    def resolve
      conversations = scope.where(organization_id: user.organization_id)
      return conversations if user.internal?

      conversations.client
                   .where(client_account_id: user.client_account_ids)
                   .joins(:conversation_memberships)
                   .where(conversation_memberships: { user_id: user.id })
                   .distinct
    end
  end

  private

  def visible_to_user?
    return false unless belongs_to_current_organization?
    return true if user.internal?

    record.client? && user.client_account_ids.include?(record.client_account_id) &&
      record.conversation_memberships.exists?(user_id: user.id)
  end
end

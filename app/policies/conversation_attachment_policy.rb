class ConversationAttachmentPolicy < ApplicationPolicy
  def view?
    conversation_policy.view?
  end

  def create?
    conversation_policy.create_message?
  end

  def update?
    create?
  end

  def destroy?
    return false unless conversation_policy.create_message?

    record.uploaded_by_id == user.id || user.organization_admin? || user.platform_owner?
  end

  class Scope < Scope
    def resolve
      scope.where(conversation_id: ConversationPolicy::Scope.new(user, Conversation).resolve.select(:id))
    end
  end

  private

  def conversation_policy
    @conversation_policy ||= ConversationPolicy.new(user, record.conversation)
  end
end

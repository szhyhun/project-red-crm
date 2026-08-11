class Api::V1::ConversationMembershipsController < Api::V1::BaseController
  def create
    conversation = policy_scope(Conversation).find(params[:conversation_id])
    authorize conversation, :manage_members?
    user = Current.organization.users.active.find(membership_params[:user_id])
    validate_participant!(conversation, user)
    membership = conversation.conversation_memberships.find_or_create_by!(user: user) do |record|
      record.role = :participant
    end

    render json: { membership: serialize(membership) }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def destroy
    conversation = policy_scope(Conversation).find(params[:conversation_id])
    authorize conversation, :manage_members?
    membership = conversation.conversation_memberships.find(params[:id])
    if membership.manager? && conversation.conversation_memberships.manager.one?
      membership.errors.add(:base, "A conversation must keep at least one manager")
      return render_validation_errors(membership)
    end

    membership.destroy!
    head :no_content
  end

  private

  def membership_params
    params.require(:conversation_membership).permit(:user_id)
  end

  def validate_participant!(conversation, user)
    allowed = if conversation.internal?
      user.internal?
    else
      user.internal? || user.client_account_ids.include?(conversation.client_account_id)
    end
    return if allowed

    conversation.errors.add(:base, "User cannot participate in this conversation")
    raise ActiveRecord::RecordInvalid.new(conversation)
  end

  def serialize(membership)
    membership.slice(:id, :role).merge(user: membership.user.slice(:id, :name, :email, :role))
  end
end

class Api::V1::ConversationsController < Api::V1::BaseController
  def index
    conversations = policy_scope(Conversation).includes(:listing, :client_account, conversation_memberships: :user).order(last_message_at: :desc, created_at: :desc)
    conversations = conversations.where(listing_id: params[:listing_id]) if params[:listing_id].present?
    authorize Conversation, :index?
    render json: { conversations: conversations.map { |conversation| serialize(conversation) } }
  end

  def show
    conversation = policy_scope(Conversation).includes(conversation_memberships: :user, messages: :author).find(params[:id])
    authorize conversation
    mark_read!(conversation)
    render json: { conversation: serialize(conversation, include_messages: true) }
  end

  def create
    listing = policy_scope(Listing).find(create_params[:listing_id]) if create_params[:listing_id].present?
    client_account = if create_params[:client_account_id].present?
      policy_scope(ClientAccount).find(create_params[:client_account_id])
    else
      listing&.client_account
    end
    authorize Conversation, :create?
    attributes = create_params.except(:listing_id, :client_account_id, :member_ids, :body)
    conversation = Current.organization.conversations.build(attributes.merge(listing: listing))
    conversation.client_account = client_account if conversation.client?

    Conversation.transaction do
      conversation.save!
      member_ids = [ current_user.id, *Array(create_params[:member_ids]).map(&:to_i) ]
      member_ids.concat(conversation.client_account.users.active.ids) if conversation.client? && conversation.client_account.present?
      member_ids.uniq!
      users = Current.organization.users.active.where(id: member_ids)
      raise ActiveRecord::RecordInvalid.new(conversation) unless users.size == member_ids.size
      if conversation.internal? && users.any? { |user| !user.internal? }
        conversation.errors.add(:base, "Internal conversations can include only organization staff")
        raise ActiveRecord::RecordInvalid.new(conversation)
      end

      users.each { |member| conversation.conversation_memberships.create!(user: member, role: member == current_user ? :manager : :participant) }
      create_message!(conversation, create_params[:body]) if create_params[:body].present?
    end

    render json: { conversation: serialize(conversation, include_messages: true) }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def create_message
    conversation = policy_scope(Conversation).find(params[:id])
    authorize conversation
    message = create_message!(conversation, message_params.fetch(:body), message_params[:visibility])
    render json: { message: serialize_message(message) }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  private

  def create_params
    params.require(:conversation).permit(:listing_id, :client_account_id, :kind, :subject, :body, member_ids: [])
  end

  def message_params
    params.require(:message).permit(:body, :visibility)
  end

  def create_message!(conversation, body, visibility = nil)
    message_visibility = current_user.internal? ? (visibility || :participants) : :participants
    message = conversation.messages.create!(author: current_user, body: body, visibility: message_visibility)
    conversation.update!(last_message_at: message.created_at)
    message
  end

  def visible_messages(conversation)
    messages = conversation.messages.includes(:author).order(:created_at)
    current_user.internal? ? messages : messages.participants
  end

  # Opening a conversation is what marks it read; there is no separate action for
  # it, so the count cannot drift from what the operator has actually seen.
  def mark_read!(conversation)
    membership = conversation.conversation_memberships.find_by(user: current_user)
    membership&.update_columns(last_read_at: Time.current, updated_at: Time.current)
  end

  # One grouped query for the whole list rather than a count per conversation.
  # A membership with a null last_read_at has never been opened, so every
  # message in it is unread.
  def unread_counts
    @unread_counts ||= begin
      scope = Message
              .joins("INNER JOIN conversation_memberships cm ON cm.conversation_id = messages.conversation_id")
              .where("cm.user_id = ?", current_user.id)
              .where("messages.created_at > COALESCE(cm.last_read_at, '-infinity'::timestamp)")
              .where.not(messages: { author_id: current_user.id })
      scope = scope.participants unless current_user.internal?
      scope.group("messages.conversation_id").count
    end
  end

  def serialize(conversation, include_messages: false)
    data = conversation.slice(:id, :listing_id, :client_account_id, :kind, :subject, :last_message_at, :created_at).merge(
      unread_count: unread_counts.fetch(conversation.id, 0),
      listing: conversation.listing && { id: conversation.listing.id, address: conversation.listing.address },
      client_account: conversation.client_account && conversation.client_account.slice(:id, :name),
      members: conversation.conversation_memberships.sort_by { |membership| membership.user.name }.map do |membership|
        membership.user.slice(:id, :name, :email, :role).merge(membership_id: membership.id, membership_role: membership.role)
      end,
      can_manage_members: policy(conversation).manage_members?
    )
    return data unless include_messages

    data.merge(messages: visible_messages(conversation).map { |message| serialize_message(message) })
  end

  def serialize_message(message)
    message.slice(:id, :body, :visibility, :attachments, :created_at).merge(author: message.author.slice(:id, :name, :role))
  end
end

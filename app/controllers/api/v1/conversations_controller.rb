class Api::V1::ConversationsController < Api::V1::BaseController
  def index
    conversations = policy_scope(Conversation).includes(:listing, :client_account, :conversation_memberships).order(last_message_at: :desc, created_at: :desc)
    conversations = conversations.where(listing_id: params[:listing_id]) if params[:listing_id].present?
    authorize Conversation, :index?
    render json: { conversations: conversations.map { |conversation| serialize(conversation) } }
  end

  def show
    conversation = policy_scope(Conversation).includes(messages: :author).find(params[:id])
    authorize conversation
    render json: { conversation: serialize(conversation, include_messages: true) }
  end

  def create
    listing = policy_scope(Listing).find(create_params.fetch(:listing_id))
    authorize Conversation, :create?
    conversation = Current.organization.conversations.build(create_params.except(:listing_id, :member_ids, :body).merge(listing: listing, client_account: listing.client_account))

    Conversation.transaction do
      conversation.save!
      member_ids = [current_user.id, *Array(create_params[:member_ids]).map(&:to_i)]
      member_ids.concat(conversation.client_account.users.active.ids) if conversation.client? && conversation.client_account.present?
      member_ids.uniq!
      users = Current.organization.users.where(id: member_ids)
      raise ActiveRecord::RecordInvalid.new(conversation) unless users.size == member_ids.size

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
    params.require(:conversation).permit(:listing_id, :kind, :subject, :body, member_ids: [])
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

  def serialize(conversation, include_messages: false)
    data = conversation.slice(:id, :listing_id, :client_account_id, :kind, :subject, :last_message_at, :created_at).merge(
      listing: conversation.listing && { id: conversation.listing.id, address: conversation.listing.address },
      client_account: conversation.client_account && conversation.client_account.slice(:id, :name)
    )
    return data unless include_messages

    data.merge(messages: visible_messages(conversation).map { |message| serialize_message(message) })
  end

  def serialize_message(message)
    message.slice(:id, :body, :visibility, :attachments, :created_at).merge(author: message.author.slice(:id, :name, :role))
  end
end

class Api::V1::ConversationsController < Api::V1::BaseController
  def index
    conversations = policy_scope(Conversation).includes(:listing, :client_account, conversation_memberships: :user)
    if params[:listing_id].present? && params[:client_account_id].present?
      # A listing workspace needs both legacy listing-linked rooms and the
      # account-wide customer room that replaced them.
      conversations = conversations.where(listing_id: params[:listing_id]).or(conversations.where(client_account_id: params[:client_account_id]))
    elsif params[:listing_id].present?
      conversations = conversations.where(listing_id: params[:listing_id])
    elsif params[:client_account_id].present?
      conversations = conversations.where(client_account_id: params[:client_account_id])
    end
    authorize Conversation, :index?
    conversations = conversations.to_a
    conversations.sort_by! do |conversation|
      if conversation.client?
        last_activity = conversation.last_message_at || conversation.created_at
        [ 0, -last_activity.to_f, conversation.id ]
      else
        membership = conversation.conversation_memberships.find { |item| item.user_id == current_user.id }
        position = membership&.position
        [ 1, position.nil? ? 1 : 0, position || 0, conversation.created_at.to_f, conversation.id ]
      end
    end
    render json: { conversations: conversations.map { |conversation| serialize(conversation) } }
  end

  def reorder
    authorize Current.organization.conversations.build(kind: :internal), :reorder?
    conversation_ids = Array(params.require(:conversation_ids)).map(&:to_i)
    if conversation_ids.empty? || conversation_ids.uniq.length != conversation_ids.length
      return render json: { error: "invalid_conversation_order" }, status: :unprocessable_entity
    end

    conversations = policy_scope(Conversation).internal.where(id: conversation_ids)
    memberships = current_user.conversation_memberships.where(conversation_id: conversation_ids).index_by(&:conversation_id)
    if conversations.size != conversation_ids.size || memberships.size != conversation_ids.size
      return render json: { error: "invalid_conversation_order" }, status: :unprocessable_entity
    end

    ConversationMembership.transaction do
      conversation_ids.each_with_index do |conversation_id, position|
        memberships.fetch(conversation_id).update!(position:)
      end
    end

    render json: { conversation_ids: }
  end

  def show
    conversation = policy_scope(Conversation).includes(
      conversation_memberships: :user,
      messages: [ :author, :listing, :order_deliverable, :media_review, :conversation_attachments,
                  { message_media_references: :media_asset } ]
    ).find(params[:id])
    authorize conversation
    mark_read!(conversation)
    render json: { conversation: serialize(conversation, include_messages: true) }
  end

  def create
    authorize Conversation, :create?
    listing = policy_scope(Listing).find(create_params[:listing_id]) if create_params[:listing_id].present?
    attributes = create_params.except(:listing_id, :client_account_id, :client_account_ids, :member_ids, :body, :body_html)
    client_conversation = create_params[:kind].to_s == "client"
    client_accounts, invalid_client_account_ids = selected_client_accounts(listing)

    if invalid_client_account_ids.any?
      invalid = Current.organization.conversations.build(attributes)
      invalid.errors.add(:client_account_ids, "contains an unavailable customer account")
      return render_validation_errors(invalid)
    end

    if client_conversation && listing.present? && client_accounts.any? { |account| !listing_belongs_to_account?(listing, account) }
      invalid = Current.organization.conversations.build(attributes.merge(listing:))
      invalid.errors.add(:listing, "must belong to the selected customer account")
      return render_validation_errors(invalid)
    end

    conversations = if client_conversation
      if client_accounts.empty?
        [ Current.organization.conversations.build(attributes.merge(listing: nil)) ]
      else
        # Client visibility is account-bound, so a multi-select fans out to
        # one private account thread per customer instead of sharing data
        # between unrelated customer portals.
        client_accounts.map do |client_account|
          Conversation.account_thread_for(
            organization: Current.organization,
            client_account:,
            subject: attributes[:subject].presence || "Client conversation"
          ).tap do |conversation|
            conversation.assign_attributes(attributes.merge(listing: nil, client_account:)) unless conversation.persisted?
          end
        end
      end
    else
      [ Current.organization.conversations.build(attributes.merge(listing:)) ]
    end

    Conversation.transaction do
      conversations.each do |conversation|
        conversation.save! unless conversation.persisted?
        add_conversation_memberships!(conversation)
        if create_params[:body].present? || create_params[:body_html].present?
          create_message!(conversation, create_params[:body], create_params[:body_html], nil, listing:)
        end
      end
    end

    serialized = conversations.map { |conversation| serialize(conversation, include_messages: true) }
    render json: { conversation: serialized.first, conversations: serialized }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def update
    conversation = policy_scope(Conversation).find(params[:id])
    authorize conversation

    if conversation.update(update_params)
      render json: { conversation: serialize(conversation) }
    else
      render_validation_errors(conversation)
    end
  end

  def destroy
    conversation = policy_scope(Conversation).find(params[:id])
    authorize conversation
    # Memberships and messages are `dependent: :destroy`, so the thread goes with it.
    conversation.destroy!
    head :no_content
  end

  def create_message
    conversation = policy_scope(Conversation).find(params[:id])
    authorize conversation
    @message_conversation = conversation
    body = message_params[:body].presence || message_params[:body_html]
    message = create_message!(conversation, body, message_params[:body_html], message_params[:visibility],
                              listing: resolve_message_listing(message_params[:listing_id]),
                              order_deliverable: resolve_message_deliverable(message_params[:order_deliverable_id]),
                              media_asset_ids: message_params[:media_asset_ids])
    render json: { message: serialize_message(message) }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  private

  def create_params
    params.require(:conversation).permit(:listing_id, :client_account_id, :kind, :subject, :retention_period, :body, :body_html,
                                         client_account_ids: [], member_ids: [])
  end

  def selected_client_accounts(listing)
    explicit_ids = Array(create_params[:client_account_ids])
    explicit_ids = [ create_params[:client_account_id] ] if explicit_ids.empty? && create_params[:client_account_id].present?
    explicit_ids = [ listing.client_account_id ] if explicit_ids.empty? && listing.present?
    return [ [], [] ] if explicit_ids.empty?

    ids = explicit_ids.map { |id| Integer(id, exception: false) }
    return [ [], ids ] if ids.any?(&:nil?)

    ids.uniq!
    accounts = policy_scope(ClientAccount).where(id: ids).index_by(&:id)
    [ ids.filter_map { |id| accounts[id] }, ids - accounts.keys ]
  end

  def listing_belongs_to_account?(listing, client_account)
    listing.client_account_id == client_account.id || listing.listing_customers.exists?(client_account_id: client_account.id)
  end

  def add_conversation_memberships!(conversation)
    member_ids = [ current_user.id, *Array(create_params[:member_ids]).map(&:to_i) ]
    member_ids.concat(conversation.client_account.users.active.ids) if conversation.client? && conversation.client_account.present?
    member_ids.uniq!
    users = Current.organization.users.active.where(id: member_ids)
    unless users.size == member_ids.size
      conversation.errors.add(:member_ids, "contains an unavailable organization member")
      raise ActiveRecord::RecordInvalid.new(conversation)
    end
    if conversation.internal? && users.any? { |user| !user.internal? }
      conversation.errors.add(:base, "Internal conversations can include only organization staff")
      raise ActiveRecord::RecordInvalid.new(conversation)
    end

    users.each do |member|
      conversation.conversation_memberships.find_or_create_by!(user: member) do |membership|
        membership.role = member == current_user ? :manager : :participant
      end
    end
  end

  def update_params
    params.require(:conversation).permit(:retention_period)
  end

  def message_params
    params.require(:message).permit(:body, :body_html, :visibility, :listing_id, :order_deliverable_id, media_asset_ids: [])
  end

  # Nothing about telling other people may stop a message being sent. The
  # enqueue itself needs Redis too, so even that is contained: a message that
  # saved is sent, and a notification that could not be queued is logged rather
  # than raised at the person who wrote it.
  def notify_later(message)
    Conversations::NotifyJob.perform_later(message.id)
  rescue StandardError => error
    Rails.logger.error("Could not queue conversation notification for message #{message.id}: #{error.class}: #{error.message}")
  end

  def create_message!(conversation, body, body_html = nil, visibility = nil, listing: nil, order_deliverable: nil, media_asset_ids: [])
    message_visibility = current_user.internal? ? (visibility || :participants) : :participants
    message = nil
    Conversation.transaction do
      message = conversation.messages.create!(author: current_user, body: body, body_html: body_html,
                                              visibility: message_visibility, listing:, order_deliverable:)
      asset_ids = Array(media_asset_ids).map(&:to_i).uniq
      assets = policy_scope(MediaAsset).where(id: asset_ids).to_a
      raise ActiveRecord::RecordNotFound if assets.size != asset_ids.size
      if order_deliverable.present? && assets.any? { |asset| asset.order_deliverable_id != order_deliverable.id }
        raise ActiveRecord::RecordNotFound
      end
      if listing.present? && assets.any? { |asset| asset.listing_id != listing.id }
        raise ActiveRecord::RecordNotFound
      end
      assets.each_with_index { |asset, position| message.message_media_references.create!(media_asset: asset, position:) }
    end
    conversation.update!(last_message_at: message.created_at)
    notify_later(message)
    message
  end

  def resolve_message_listing(id)
    return if id.blank?

    listing = policy_scope(Listing).find(id)
    return listing if current_user.internal?
    return listing if listing.client_account_id == @message_conversation&.client_account_id
    return listing if listing.listing_customers.where(client_account_id: @message_conversation&.client_account_id).exists?

    raise ActiveRecord::RecordNotFound
  end

  def resolve_message_deliverable(id)
    return if id.blank?

    deliverable = policy_scope(OrderDeliverable).find(id)
    return deliverable if current_user.internal?
    return deliverable if deliverable.listing&.client_account_id == @message_conversation&.client_account_id
    return deliverable if deliverable.listing&.listing_customers&.where(client_account_id: @message_conversation&.client_account_id)&.exists?

    raise ActiveRecord::RecordNotFound
  end

  def visible_messages(conversation)
    messages = conversation.messages.includes(:author, :conversation_attachments, message_media_references: :media_asset).order(:created_at)
    current_user.internal? ? messages : messages.participants
  end

  # Opening a conversation is what marks it read; there is no separate action for
  # it, so the count cannot drift from what the operator has actually seen.
  def mark_read!(conversation)
    membership = conversation.conversation_memberships.find_by(user: current_user)
    if membership.blank? && (current_user.organization_admin? || current_user.platform_owner?) && conversation.client?
      membership = conversation.conversation_memberships.create!(user: current_user, role: :participant)
    end
    membership&.update_columns(last_read_at: Time.current, updated_at: Time.current)
  end

  # One grouped query for the whole list rather than a count per conversation.
  # A membership with a null last_read_at has never been opened, so every
  # message in it is unread. The timestamp is retained for the client-side
  # unread indicator and future notification details; it does not reorder rooms.
  def unread_message_stats
    @unread_message_stats ||= begin
      rows = unread_message_scope
             .group("messages.conversation_id")
             .pluck("messages.conversation_id", Arel.sql("COUNT(messages.id)"), Arel.sql("MAX(messages.created_at)"))
      rows.to_h do |conversation_id, count, last_unread_message_at|
        [ conversation_id, { count:, last_unread_message_at: } ]
      end
    end
  end

  def unread_message_scope
    scope = Message.joins(:conversation)
    if current_user.organization_admin? || current_user.platform_owner?
      # Organization admins can see every customer thread without being listed
      # as a participant, so their unread state needs a left join. Opening the
      # thread creates the membership that stores the admin's read marker.
      scope = scope
               .joins("LEFT JOIN conversation_memberships cm ON cm.conversation_id = messages.conversation_id AND cm.user_id = #{current_user.id}")
               .where(conversations: { organization_id: current_user.organization_id })
               .where("cm.id IS NOT NULL OR conversations.kind = ?", Conversation.kinds.fetch("client"))
    else
      scope = scope
               .joins("INNER JOIN conversation_memberships cm ON cm.conversation_id = messages.conversation_id")
               .where("cm.user_id = ?", current_user.id)
    end

    scope = scope
             .where("messages.created_at > COALESCE(cm.last_read_at, '-infinity'::timestamp)")
             .where.not(messages: { author_id: current_user.id })
    scope = scope.participants unless current_user.internal?
    scope
  end

  def serialize(conversation, include_messages: false)
    unread = unread_message_stats.fetch(conversation.id, { count: 0, last_unread_message_at: nil })
    membership = conversation.conversation_memberships.find { |item| item.user_id == current_user.id }
    data = conversation.slice(:id, :listing_id, :client_account_id, :kind, :subject, :retention_period, :last_message_at, :created_at).merge(
      unread_count: unread[:count],
      last_unread_message_at: unread[:last_unread_message_at],
      position: membership&.position,
      listing: conversation.listing && { id: conversation.listing.id, address: conversation.listing.address },
      client_account: conversation.client_account && conversation.client_account.slice(:id, :name),
      can_delete: policy(conversation).destroy?,
      members: conversation.conversation_memberships.sort_by { |membership| membership.user.name }.map do |membership|
        membership.user.slice(:id, :name, :email, :role).merge(membership_id: membership.id, membership_role: membership.role)
      end,
      can_manage_members: policy(conversation).manage_members?
    )
    return data unless include_messages

    data.merge(messages: visible_messages(conversation).map { |message| serialize_message(message) })
  end

  def serialize_message(message)
    message.slice(:id, :body, :body_html, :visibility, :message_kind, :listing_id, :order_deliverable_id,
                  :media_review_id, :created_at).merge(
      context: serialize_message_context(message),
      attachments: message.conversation_attachments.order(:created_at, :id).map { |attachment| ConversationAttachment.serialize(attachment) },
      media_references: message.message_media_references.includes(:media_asset).order(:position, :id).filter_map do |reference|
        asset = reference.media_asset
        next if asset.blank?

        {
          id: asset.id,
          filename: asset.filename,
          content_type: asset.content_type,
          byte_size: asset.byte_size,
          preview_path: asset.ready? && !asset.external? ? preview_api_v1_media_asset_path(asset) : nil,
          download_path: asset.ready? && !asset.external? ? download_api_v1_media_asset_path(asset) : nil
        }
      end,
      author: message.author.slice(:id, :name, :role)
    )
  end

  def serialize_message_context(message)
    context = {}
    context[:listing] = { id: message.listing.id, address: message.listing.address } if message.listing.present?
    if message.order_deliverable.present?
      context[:deliverable] = message.order_deliverable.slice(:id, :title, :deliverable_type)
    end

    selected_asset_count = message.message_media_references.size
    context[:selected_asset_count] = selected_asset_count if selected_asset_count.positive?
    if message.media_review.present?
      context[:review] = message.media_review.slice(:id, :number, :status, :outcome).merge(listing_id: message.media_review.listing_id)
    end
    context.presence
  end
end

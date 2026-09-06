class Api::V1::ConversationAttachmentsController < Api::V1::BaseController
  before_action :set_conversation
  before_action :set_message

  def create
    authorize @conversation, :create_message?
    attachments = upload_files
    render json: { conversation_attachments: attachments.map { |attachment| ConversationAttachment.serialize(attachment) } }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  rescue ConversationStorage::MissingFile, ConversationStorage::WriteError => error
    Rails.logger.warn("Conversation attachment upload failed: #{error.class}: #{error.message}")
    render json: { error: "upload_failed" }, status: :unprocessable_entity
  end

  def preview
    attachment = find_attachment
    authorize attachment, :view?
    return render json: { error: "attachment_not_ready" }, status: :unprocessable_entity unless attachment.ready?

    return stream_preview(attachment) if ConversationStorage.s3?

    disposition = PrivateAttachmentContentType.safe_inline?(attachment.content_type) ? "inline" : "attachment"
    response_type = disposition == "inline" ? attachment.content_type : "application/octet-stream"
    send_file ConversationStorage.path_for(attachment.storage_key),
              type: response_type,
              disposition:,
              filename: attachment.filename
  rescue ConversationStorage::MissingFile
    render json: { error: "attachment_missing" }, status: :not_found
  end

  def download
    attachment = find_attachment
    authorize attachment, :view?
    return render json: { error: "attachment_not_ready" }, status: :unprocessable_entity unless attachment.ready?

    disposition = "attachment; filename=\"#{attachment.filename.to_s.gsub(/[^\w. -]/, "_")}\""
    return redirect_to ConversationStorage.temporary_url(attachment.storage_key, disposition:), allow_other_host: true if ConversationStorage.s3?

    send_file ConversationStorage.path_for(attachment.storage_key),
              type: "application/octet-stream",
              disposition: "attachment",
              filename: attachment.filename
  rescue ConversationStorage::MissingFile
    render json: { error: "attachment_missing" }, status: :not_found
  end

  def destroy
    attachment = find_attachment
    authorize attachment, :destroy?
    ConversationStorage.delete(attachment.storage_key)
    attachment.destroy!
    head :no_content
  end

  private

  def set_conversation
    @conversation = policy_scope(Conversation).find(params[:conversation_id])
  end

  def set_message
    @message = @conversation.messages.find(params[:message_id])
  end

  def find_attachment
    @message.conversation_attachments.find(params[:id])
  end

  def upload_files
    files = Array(params[:files]).presence || [ params.require(:file) ]
    files.map { |uploaded_file| upload_one(uploaded_file) }
  end

  def upload_one(uploaded_file)
    content_type = UploadContentType.for(uploaded_file)
    storage_key = ConversationStorage.key_for(
      organization: Current.organization,
      conversation: @conversation,
      message: @message,
      filename: uploaded_file.original_filename
    )
    attachment = Current.organization.conversation_attachments.build(
      conversation: @conversation,
      message: @message,
      uploaded_by: current_user,
      status: :pending,
      storage_key:,
      filename: uploaded_file.original_filename,
      content_type:,
      byte_size: uploaded_file.size
    )
    unless content_type.match?(ConversationAttachment::ALLOWED_CONTENT_TYPES)
      attachment.errors.add(:content_type, "is not supported for conversation attachments")
      raise ActiveRecord::RecordInvalid, attachment
    end

    authorize attachment, :create?
    attachment.save!

    ConversationStorage.write(upload: uploaded_file.tempfile, key: storage_key, content_type:)
    attachment.update!(status: :ready, processed_at: Time.current)
    attachment
  rescue ConversationStorage::MissingFile, ConversationStorage::WriteError => error
    ConversationStorage.delete(storage_key) if storage_key.present?
    Rails.logger.warn("Conversation attachment storage failed: #{error.class}: #{error.message}")
    attachment&.update(status: :failed, metadata: attachment.metadata.merge("processing_error" => "upload_failed"))
    raise
  end

  def stream_preview(attachment)
    return render json: { error: "attachment_missing" }, status: :not_found unless ConversationStorage.exist?(attachment.storage_key)

    safe_inline = PrivateAttachmentContentType.safe_inline?(attachment.content_type)
    response.headers["Content-Type"] = safe_inline ? attachment.content_type : "application/octet-stream"
    response.headers["Content-Length"] = attachment.byte_size.to_s
    response.headers["Content-Disposition"] = ActionDispatch::Http::ContentDisposition.format(
      disposition: safe_inline ? "inline" : "attachment", filename: attachment.filename
    )
    response.headers["Cache-Control"] = "private, no-store"
    self.response_body = ConversationStorage.stream(attachment.storage_key)
  end
end

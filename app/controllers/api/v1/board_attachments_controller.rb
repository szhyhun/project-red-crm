class Api::V1::BoardAttachmentsController < Api::V1::BaseController
  before_action :set_task

  def create_task
    authorize @task, :update?
    attachments = upload_files(comment: nil)
    record_activity("board_attachment.created", attachment_ids: attachments.map(&:id))
    render json: { board_attachments: attachments.map { |attachment| BoardAttachment.serialize(attachment) } }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  rescue BoardStorage::MissingFile, BoardStorage::WriteError => error
    Rails.logger.warn("Board attachment upload failed: #{error.class}: #{error.message}")
    render json: { error: "upload_failed" }, status: :unprocessable_entity
  end

  def create_comment
    comment = @task.task_comments.find(params[:task_comment_id])
    authorize comment, :update?
    attachments = upload_files(comment:)
    record_activity("board_attachment.created", attachment_ids: attachments.map(&:id), comment_id: comment.id)
    render json: { board_attachments: attachments.map { |attachment| BoardAttachment.serialize(attachment) } }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  rescue BoardStorage::MissingFile, BoardStorage::WriteError => error
    Rails.logger.warn("Board attachment upload failed: #{error.class}: #{error.message}")
    render json: { error: "upload_failed" }, status: :unprocessable_entity
  end

  def preview
    attachment = find_attachment
    authorize attachment, :view?
    return render json: { error: "attachment_not_ready" }, status: :unprocessable_entity unless attachment.ready?

    return stream_preview(attachment) if BoardStorage.s3?

    disposition = PrivateAttachmentContentType.safe_inline?(attachment.content_type) ? "inline" : "attachment"
    response_type = disposition == "inline" ? attachment.content_type : "application/octet-stream"
    send_file BoardStorage.path_for(attachment.storage_key),
              type: response_type,
              disposition:,
              filename: attachment.filename
  rescue BoardStorage::MissingFile
    render json: { error: "attachment_missing" }, status: :not_found
  end

  def download
    attachment = find_attachment
    authorize attachment, :view?
    return render json: { error: "attachment_not_ready" }, status: :unprocessable_entity unless attachment.ready?

    disposition = "attachment; filename=\"#{attachment.filename.to_s.gsub(/[^\w. -]/, "_")}\""
    return redirect_to BoardStorage.temporary_url(attachment.storage_key, disposition:), allow_other_host: true if BoardStorage.s3?

    send_file BoardStorage.path_for(attachment.storage_key),
              type: "application/octet-stream",
              disposition: "attachment",
              filename: attachment.filename
  rescue BoardStorage::MissingFile
    render json: { error: "attachment_missing" }, status: :not_found
  end

  def destroy
    attachment = find_attachment
    authorize attachment
    record_activity("board_attachment.deleted", attachment_id: attachment.id)
    BoardStorage.delete(attachment.storage_key)
    attachment.destroy!
    head :no_content
  end

  private

  def set_task
    @task = policy_scope(WorkflowTask).find(params[:workflow_task_id])
  end

  def find_attachment
    @task.board_attachments.find(params[:id])
  end

  def stream_preview(attachment)
    return render json: { error: "attachment_missing" }, status: :not_found unless BoardStorage.exist?(attachment.storage_key)

    safe_inline = PrivateAttachmentContentType.safe_inline?(attachment.content_type)
    response.headers["Content-Type"] = safe_inline ? attachment.content_type : "application/octet-stream"
    response.headers["Content-Length"] = attachment.byte_size.to_s
    response.headers["Content-Disposition"] = ActionDispatch::Http::ContentDisposition.format(
      disposition: safe_inline ? "inline" : "attachment", filename: attachment.filename
    )
    response.headers["Cache-Control"] = "private, no-store"
    self.response_body = BoardStorage.stream(attachment.storage_key)
  end

  def upload_files(comment:)
    files = Array(params[:files]).presence || [ params.require(:file) ]
    files.map { |uploaded_file| upload_one(uploaded_file, comment:) }
  end

  def upload_one(uploaded_file, comment:)
    content_type = UploadContentType.for(uploaded_file)
    storage_key = BoardStorage.key_for(
      organization: Current.organization,
      board: @task.board,
      task: @task,
      filename: uploaded_file.original_filename
    )
    attachment = Current.organization.board_attachments.build(
      board: @task.board,
      workflow_task: @task,
      task_comment: comment,
      uploaded_by: current_user,
      status: :pending,
      storage_key:,
      filename: uploaded_file.original_filename,
      content_type:,
      byte_size: uploaded_file.size
    )
    unless content_type.match?(BoardAttachment::ALLOWED_CONTENT_TYPES)
      attachment.errors.add(:content_type, "is not supported for board attachments")
      raise ActiveRecord::RecordInvalid, attachment
    end

    authorize attachment, :create?
    attachment.save!

    BoardStorage.write(upload: uploaded_file.tempfile, key: storage_key, content_type:)
    attachment.update!(status: :ready, processed_at: Time.current)
    attachment
  rescue BoardStorage::MissingFile, BoardStorage::WriteError => error
    BoardStorage.delete(storage_key) if storage_key.present?
    Rails.logger.warn("Board attachment storage failed: #{error.class}: #{error.message}")
    attachment&.update(status: :failed, metadata: attachment.metadata.merge("processing_error" => "upload_failed"))
    raise
  end

  def record_activity(event_type, payload = {})
    ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: @task, event_type:, payload:)
  end
end

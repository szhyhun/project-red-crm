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
    render json: { error: "upload_failed", details: error.message }, status: :unprocessable_entity
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
    render json: { error: "upload_failed", details: error.message }, status: :unprocessable_entity
  end

  def preview
    attachment = find_attachment
    authorize attachment, :view?
    return render json: { error: "attachment_not_ready" }, status: :unprocessable_entity unless attachment.ready?

    return redirect_to BoardStorage.temporary_url(attachment.storage_key, content_type: attachment.content_type, disposition: "inline"), allow_other_host: true if BoardStorage.s3?

    send_file BoardStorage.path_for(attachment.storage_key),
              type: attachment.content_type,
              disposition: "inline",
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

  def upload_files(comment:)
    files = Array(params[:files]).presence || [ params.require(:file) ]
    files.map { |uploaded_file| upload_one(uploaded_file, comment:) }
  end

  def upload_one(uploaded_file, comment:)
    content_type = upload_content_type(uploaded_file)
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
    authorize attachment, :create?
    attachment.save!

    BoardStorage.write(upload: uploaded_file.tempfile, key: storage_key, content_type:)
    attachment.update!(status: :ready, processed_at: Time.current)
    attachment
  rescue BoardStorage::MissingFile, BoardStorage::WriteError => error
    BoardStorage.delete(storage_key) if storage_key.present?
    attachment&.update(status: :failed, metadata: attachment.metadata.merge("processing_error" => error.message))
    raise
  end

  def upload_content_type(uploaded_file)
    declared_type = uploaded_file.content_type.presence
    return declared_type if declared_type.present? && declared_type != "application/octet-stream"

    Marcel::MimeType.for(name: uploaded_file.original_filename).presence || declared_type || "application/octet-stream"
  end

  def record_activity(event_type, payload = {})
    ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: @task, event_type:, payload:)
  end
end

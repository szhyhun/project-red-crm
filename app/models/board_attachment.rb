class BoardAttachment < ApplicationRecord
  belongs_to :organization
  belongs_to :board
  belongs_to :workflow_task
  belongs_to :task_comment, optional: true
  belongs_to :uploaded_by, class_name: "User", optional: true

  enum :status, { pending: "pending", ready: "ready", failed: "failed" }, validate: true

  ALLOWED_CONTENT_TYPES = %r{
    \A(?:
      image/[^\s;]+|
      video/[^\s;]+|
      application/(?:pdf|zip|gzip|msword|vnd\.openxmlformats-officedocument\.[^\s;]+|vnd\.ms-excel[^\s;]*|vnd\.ms-powerpoint[^\s;]*)|
      text/(?:plain|csv|markdown)
    )\z
  }ix

  validates :filename, :content_type, :storage_key, presence: true
  validates :byte_size, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: ->(_record) { BoardAttachment.max_bytes } }
  validate :content_type_is_supported
  validate :parent_records_match

  def self.max_bytes
    ENV.fetch("BOARD_MEDIA_MAX_BYTES", 500.megabytes).to_i
  end

  def self.serialize(attachment)
    attachment.slice(:id, :board_id, :workflow_task_id, :task_comment_id, :status, :filename,
                     :content_type, :byte_size, :width, :height, :duration_seconds, :metadata,
                     :processed_at, :created_at).merge(
      # Consumers receive authorized API routes; storage keys stay private even
      # when the application is configured with a CDN for board media.
      cdn_url: nil,
      preview_path: "/api/v1/workflow_tasks/#{attachment.workflow_task_id}/attachments/#{attachment.id}/preview",
      download_path: "/api/v1/workflow_tasks/#{attachment.workflow_task_id}/attachments/#{attachment.id}/download",
      uploaded_by: attachment.uploaded_by&.slice(:id, :name)
    )
  end

  private

  def content_type_is_supported
    return if content_type.to_s.match?(ALLOWED_CONTENT_TYPES)

    errors.add(:content_type, "is not supported for board attachments")
  end

  def parent_records_match
    if task_comment.present? && task_comment.workflow_task_id != workflow_task_id
      errors.add(:task_comment, "must belong to the workflow task")
    end

    if board.present? && workflow_task.present? && board_id != workflow_task.board_id
      errors.add(:board, "must match the workflow task board")
    end

    if organization.present? && workflow_task.present? && organization_id != workflow_task.organization_id
      errors.add(:organization, "must match the workflow task organization")
    end
  end
end

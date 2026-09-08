class WorkflowTask < ApplicationRecord
  belongs_to :listing, optional: true
  belongs_to :organization
  belongs_to :board
  belongs_to :assignee, class_name: "User", optional: true
  belongs_to :reporter, class_name: "User", optional: true
  belongs_to :parent_task, class_name: "WorkflowTask", optional: true
  has_many :child_tasks, class_name: "WorkflowTask", foreign_key: :parent_task_id, dependent: :nullify
  has_many :workflow_task_placements, dependent: :destroy
  has_many :placed_boards, through: :workflow_task_placements, source: :board
  has_many :workflow_task_deliverables, dependent: :destroy
  has_many :order_deliverables, through: :workflow_task_deliverables
  has_many :task_comments, dependent: :destroy
  has_many :task_checklist_items, dependent: :destroy
  has_many :board_attachments, dependent: :destroy
  has_many :activity_events, as: :subject, dependent: :destroy
  has_many :workflow_task_labels, dependent: :destroy
  has_many :board_labels, through: :workflow_task_labels

  enum :priority, { low: "low", normal: "normal", high: "high", urgent: "urgent" }, validate: true

  scope :placed_on, ->(board) { joins(:workflow_task_placements).where(workflow_task_placements: { board_id: board }).distinct }
  scope :home_placed, -> { joins(:workflow_task_placements).where(workflow_task_placements: { is_home: true }) }

  validates :title, :status, presence: true
  validate :status_matches_board_column
  validate :listing_present_when_board_requires_one
  validate :customer_visible_on_customer_visible_board
  validate :listing_belongs_to_organization
  validate :assignee_can_work_on_board
  before_validation :normalize_description_content
  after_create :ensure_home_placement

  def home_placement
    workflow_task_placements.find_by(is_home: true) || workflow_task_placements.order(:id).first
  end

  def placement_on(board)
    workflow_task_placements.find_by(board_id: board.id)
  end

  def ensure_home_placement
    return if board.blank? || workflow_task_placements.exists?

    column = board.workflow_columns.find_by(key: status) || board.workflow_columns.ordered.first
    return if column.blank?

    workflow_task_placements.create!(board:, workflow_column: column, position:, is_home: true)
  end

  private

  def normalize_description_content
    return unless will_save_change_to_description_html?

    self.description_html = RichTextSanitizer.sanitize(description_html).presence
    self.description = RichTextSanitizer.plain_text(description_html).presence
  end

  def status_matches_board_column
    return if board.blank? || status.blank? || board.workflow_columns.where(key: status).exists?

    errors.add(:status, "must match a column on this board")
  end

  # Production boards track work against a property; internal boards track work
  # that has no property at all, so the requirement belongs to the board rather
  # than to the column.
  def listing_present_when_board_requires_one
    return if board.blank? || !board.requires_listing? || listing_id.present?

    errors.add(:listing, "is required on this board")
  end

  def customer_visible_on_customer_visible_board
    return unless customer_visible? && board.present? && !board.client_visible?

    errors.add(:customer_visible, "requires a customer-visible board")
  end

  def listing_belongs_to_organization
    return if listing.blank? || listing.organization_id == organization_id

    errors.add(:listing, "must belong to the same organization")
  end

  def assignee_can_work_on_board
    return if assignee.blank? || board.blank? || board.assignable_user?(assignee)

    errors.add(:assignee, "must have access to this board")
  end
end

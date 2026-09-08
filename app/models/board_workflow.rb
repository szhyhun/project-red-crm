class BoardWorkflow < ApplicationRecord
  TRIGGERS = %w[order_approved].freeze

  belongs_to :organization
  belongs_to :board
  belongs_to :created_by, class_name: "User", optional: true
  has_many :conditions, class_name: "BoardWorkflowCondition", dependent: :destroy
  has_many :actions, class_name: "BoardWorkflowAction", dependent: :destroy
  has_many :status_mappings, class_name: "BoardWorkflowStatusMapping", dependent: :destroy
  has_many :runs, class_name: "BoardWorkflowRun", dependent: :destroy
  accepts_nested_attributes_for :conditions, allow_destroy: true
  accepts_nested_attributes_for :actions, allow_destroy: true
  accepts_nested_attributes_for :status_mappings, allow_destroy: true

  validates :name, presence: true
  validates :trigger_key, inclusion: { in: TRIGGERS }
  validates :workflow_version, numericality: { only_integer: true, greater_than: 0 }
  validate :board_belongs_to_organization
  validate :status_mappings_complete_when_enabled

  scope :enabled, -> { where(enabled: true) }
  scope :for_trigger, ->(trigger) { where(trigger_key: trigger) }

  def conditions_match?(deliverable)
    conditions.ordered.all? { |condition| condition.matches?(deliverable) }
  end

  def missing_status_mappings
    BoardWorkflowStatusMapping::SOURCE_STATUSES - status_mappings.map(&:source_status)
  end

  def self.default_status_mapping_attributes(board)
    BoardWorkflowStatusMapping::SOURCE_STATUSES.each_with_index.map do |source_status, position|
      {
        source_status:,
        target_column_key: default_target_column_key(board, source_status),
        position:
      }
    end
  end

  private

  def status_mappings_complete_when_enabled
    return unless enabled?
    # Existing records created before status mappings were introduced remain
    # runnable through the runner's legacy first-column fallback. Any new
    # workflow, or any explicit activation of a draft, must be complete.
    return if persisted? && status_mappings.empty? && !will_save_change_to_enabled?

    missing = missing_status_mappings
    return if missing.empty?

    errors.add(:status_mappings, "must define a target column for #{missing.join(', ')}")
  end

  def self.default_target_column_key(board, source_status)
    preferred_keys = {
      "not_started" => [ "todo" ],
      "in_progress" => [ "in_progress" ],
      "in_review" => %w[review qa approval in_progress],
      "delivered" => [ "done" ]
    }.fetch(source_status, [])
    preferred_key = preferred_keys.find { |key| board.workflow_columns.exists?(key:) }
    return preferred_key if preferred_key.present?

    board.workflow_columns.ordered.find { |column| column.canonical_status == source_status }&.key ||
      board.workflow_columns.ordered.first&.key
  end

  def board_belongs_to_organization
    return if board.blank? || board.organization_id == organization_id

    errors.add(:board, "must belong to the same organization")
  end
end

class BoardWorkflowRun < ApplicationRecord
  STATUSES = %w[pending running succeeded succeeded_with_warnings failed].freeze

  belongs_to :organization
  belongs_to :board_workflow
  belongs_to :order
  has_many :steps, class_name: "BoardWorkflowRunStep", dependent: :destroy

  enum :status, STATUSES.index_by(&:itself), validate: true

  validates :idempotency_key, :triggered_at, presence: true
  validates :idempotency_key, uniqueness: true
  validates :retry_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :related_records_belong_to_organization

  scope :recent, -> { order(triggered_at: :desc, id: :desc) }

  private

  def related_records_belong_to_organization
    errors.add(:board_workflow, "must belong to the same organization") if board_workflow.present? && board_workflow.organization_id != organization_id
    errors.add(:order, "must belong to the same organization") if order.present? && order.organization_id != organization_id
  end
end

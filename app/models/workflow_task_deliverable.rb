class WorkflowTaskDeliverable < ApplicationRecord
  belongs_to :workflow_task
  belongs_to :order_deliverable

  validates :order_deliverable_id, uniqueness: { scope: :workflow_task_id }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :same_organization

  private

  def same_organization
    return if workflow_task.blank? || order_deliverable.blank?
    return if workflow_task.organization_id == order_deliverable.organization_id

    errors.add(:base, "task and deliverable must belong to the same organization")
  end
end

class WorkflowTask < ApplicationRecord
  belongs_to :listing
  belongs_to :organization
  belongs_to :assignee, class_name: "User", optional: true

  enum :priority, { low: "low", normal: "normal", high: "high", urgent: "urgent" }, validate: true

  validates :title, :stage, :status, presence: true
  validate :status_matches_organization_column

  private

  def status_matches_organization_column
    return if organization.blank? || status.blank? || organization.workflow_columns.where(key: status).exists?

    errors.add(:status, "must match a workflow column")
  end
end

class WorkflowTask < ApplicationRecord
  belongs_to :listing
  belongs_to :organization
  belongs_to :assignee, class_name: "User", optional: true

  enum :status, { todo: "todo", in_progress: "in_progress", blocked: "blocked", done: "done" }, validate: true

  validates :title, :stage, presence: true
end

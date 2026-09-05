class TaskComment < ApplicationRecord
  belongs_to :workflow_task
  belongs_to :author, class_name: "User"

  validates :body, presence: true

  scope :chronological, -> { order(:created_at, :id) }

  def edited?
    edited_at.present?
  end
end

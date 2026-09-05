class TaskChecklistItem < ApplicationRecord
  belongs_to :workflow_task
  belongs_to :completed_by, class_name: "User", optional: true

  validates :title, presence: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :ordered, -> { order(:position, :id) }

  def done?
    completed_at.present?
  end

  # Completion is a timestamp plus who did it rather than a boolean, so the
  # task detail can say when an item was ticked without a separate audit record.
  def done=(value)
    if ActiveModel::Type::Boolean.new.cast(value)
      self.completed_at ||= Time.current
    else
      self.completed_at = nil
      self.completed_by = nil
    end
  end
end

class WorkflowColumn < ApplicationRecord
  DEFAULTS = [
    { key: "todo", name: "Todo", color: "#f7f6f8", category: "active", position: 0 },
    { key: "in_progress", name: "In Progress", color: "#aec7f7", category: "active", position: 1 },
    { key: "blocked", name: "Blocked", color: "#e6190b", category: "blocked", position: 2 },
    { key: "done", name: "Done", color: "#3cb371", category: "completed", position: 3 }
  ].freeze

  belongs_to :organization

  enum :category, { active: "active", blocked: "blocked", completed: "completed" }, validate: true

  validates :name, :key, :color, presence: true
  validates :key, uniqueness: { scope: :organization_id }, format: { with: /\A[a-z0-9]+(?:_[a-z0-9]+)*\z/ }
  validates :color, format: { with: /\A#[0-9a-fA-F]{6}\z/ }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_validation :assign_key, on: :create

  scope :ordered, -> { order(:position, :id) }

  private

  def assign_key
    return if key.present? || name.blank? || organization.blank?

    base = name.parameterize(separator: "_").presence || "column"
    candidate = base
    suffix = 2
    while organization.workflow_columns.where(key: candidate).exists?
      candidate = "#{base}_#{suffix}"
      suffix += 1
    end
    self.key = candidate
  end
end

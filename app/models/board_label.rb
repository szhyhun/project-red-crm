class BoardLabel < ApplicationRecord
  COLORS = %w[#e8f7ed #e8f0ff #f1eafa #fbf4d7 #fde7e3 #e5f5f5].freeze

  belongs_to :board
  has_many :workflow_task_labels, dependent: :destroy
  has_many :workflow_tasks, through: :workflow_task_labels

  validates :name, presence: true, length: { maximum: 60 },
                    uniqueness: { scope: :board_id, case_sensitive: false }
  validates :color, presence: true, format: { with: /\A#[0-9a-fA-F]{6}\z/ }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_validation :normalize_name
  before_validation :assign_default_color, on: :create

  scope :ordered, -> { order(:position, :name, :id) }

  private

  def normalize_name
    self.name = name.to_s.strip.gsub(/\s+/, " ").presence
  end

  def assign_default_color
    self.color = COLORS.first if color.blank?
  end
end

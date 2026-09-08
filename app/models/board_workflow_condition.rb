class BoardWorkflowCondition < ApplicationRecord
  FIELDS = %w[deliverable_type service_product_id package_product_id].freeze
  OPERATORS = %w[equals not_equals in].freeze

  belongs_to :board_workflow

  validates :field, inclusion: { in: FIELDS }
  validates :operator, inclusion: { in: OPERATORS }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :ordered, -> { order(:position, :id) }

  def matches?(deliverable)
    actual = case field
    when "deliverable_type" then deliverable.deliverable_type
    when "service_product_id" then deliverable.service_product_id
    when "package_product_id" then deliverable.product_component&.package_product_id
    end
    expected = value.is_a?(Hash) ? (value["value"] || value[:value]) : value
    expected_values = Array(expected).map(&:to_s)

    case operator
    when "equals" then actual.to_s == expected_values.first
    when "not_equals" then actual.to_s != expected_values.first
    when "in" then expected_values.include?(actual.to_s)
    else false
    end
  end
end

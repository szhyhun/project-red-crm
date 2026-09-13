module Workflows
  class ActionScope
    attr_reader :run, :workflow, :order

    def initialize(run:)
      @run = run
      @workflow = run.board_workflow
      @order = run.order
    end

    def matching_deliverables
      @matching_deliverables ||= order.order_deliverables.active
                                      .includes(:service_product, product_component: :package_product)
                                      .select { |deliverable| workflow.conditions_match?(deliverable) }
    end

    def matching_tasks
      matching_deliverables.flat_map(&:workflow_tasks).uniq
    end

    def resolve_board(id)
      return workflow.board if id.blank?

      order.organization.boards.active.find(id)
    end

    def first_column_key(board)
      board.workflow_columns.ordered.first&.key || "todo"
    end

    def initial_task_status(deliverable)
      mapped_column = workflow.status_mappings.find_by(source_status: deliverable.status)&.target_column_key
      return mapped_column if mapped_column.present? && workflow.board.workflow_columns.exists?(key: mapped_column)

      first_column_key(workflow.board)
    end
  end
end

module Workflows
  module Actions
    class PlaceTasks < ApplicationInteractor
      def call
        scope = context.fetch(:scope)
        action = context.fetch(:action)
        board = scope.resolve_board(action.configuration["board_id"])
        if scope.order.listing.blank? && board.requires_listing?
          return context.set(:output, skipped: true, warning: "No listing is available for the target board")
        end

        column = board.workflow_columns.find_by(key: action.configuration["column_key"].presence) || board.workflow_columns.ordered.first
        return context.set(:output, skipped: true, warning: "The workflow has no target column") if column.blank?

        scope.matching_tasks.each_with_index do |task, index|
          placement = task.workflow_task_placements.find_or_initialize_by(board: board)
          is_home = placement.persisted? ? placement.is_home? : task.home_placement.blank?
          placement.update!(workflow_column: column, position: index, is_home:)
        end
        context.set(:output, board_id: board.id, column_id: column.id, task_ids: scope.matching_tasks.map(&:id))
      end
    end
  end
end

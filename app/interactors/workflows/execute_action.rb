module Workflows
  class ExecuteAction < ApplicationInteractor
    ACTIONS = {
      "create_parent_task" => Actions::CreateParentTask,
      "create_or_group_child_task" => Actions::CreateChildTasks,
      "place_on_board" => Actions::PlaceTasks,
      "link_deliverable" => Actions::LinkDeliverables,
      "assign_to_user" => Actions::AssignUser,
      "assign_to_group" => Actions::AssignGroup
    }.freeze

    def call
      action = context.fetch(:action)
      action_class = ACTIONS[action.action_type]
      return context.set(:output, skipped: true, warning: "Unsupported workflow action #{action.action_type}") if action_class.blank?

      action_class.call(context:)
    end
  end
end

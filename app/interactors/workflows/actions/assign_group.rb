module Workflows
  module Actions
    class AssignGroup < ApplicationInteractor
      def call
        scope = context.fetch(:scope)
        action = context.fetch(:action)
        group = scope.order.organization.user_groups.find_by(id: action.configuration["user_group_id"])
        return context.set(:output, skipped: true, warning: "The workflow group is not in this organization") if group.blank?

        scope.matching_tasks.each { |task| task.update!(metadata: task.metadata.merge("assigned_group_id" => group.id)) }
        context.set(:output, user_group_id: group.id, task_ids: scope.matching_tasks.map(&:id))
      end
    end
  end
end

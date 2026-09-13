module Workflows
  module Actions
    class AssignUser < ApplicationInteractor
      def call
        scope = context.fetch(:scope)
        action = context.fetch(:action)
        user = scope.order.organization.users.active.find_by(id: action.configuration["user_id"])
        return context.set(:output, skipped: true, warning: "The workflow assignee is not an active organization user") if user.blank?

        scope.matching_tasks.each { |task| task.update!(assignee: user) }
        context.set(:output, user_id: user.id, task_ids: scope.matching_tasks.map(&:id))
      end
    end
  end
end

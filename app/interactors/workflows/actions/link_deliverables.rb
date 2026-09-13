module Workflows
  module Actions
    class LinkDeliverables < ApplicationInteractor
      def call
        scope = context.fetch(:scope)
        scope.matching_deliverables.each do |deliverable|
          task = deliverable.workflow_tasks.first
          next if task.blank?

          task.workflow_task_deliverables.find_or_create_by!(order_deliverable: deliverable, position: deliverable.position)
        end
        context.set(:output, deliverable_ids: scope.matching_deliverables.map(&:id), task_ids: scope.matching_tasks.map(&:id))
      end
    end
  end
end

module WorkflowTasks
  class Mover
    def initialize(task:, attributes:)
      @task = task
      @attributes = attributes.symbolize_keys
    end

    def move!
      WorkflowTask.transaction do
        source_status = @task.status
        target_status = @attributes.fetch(:status, @task.status)
        target_position = normalized_position
        target_position = [target_position, 0].max

        @task.assign_attributes(@attributes.except(:position))
        @task.status = target_status
        @task.save!

        siblings = @task.organization.workflow_tasks.where(status: target_status).where.not(id: @task.id).order(:position, :id).to_a
        siblings.insert([target_position, siblings.length].min, @task)
        siblings.each_with_index do |sibling, position|
          sibling.update_columns(position:, updated_at: Time.current)
        end

        if source_status != target_status
          @task.organization.workflow_tasks.where(status: source_status).order(:position, :id).each_with_index do |sibling, position|
            sibling.update_columns(position:, updated_at: Time.current)
          end
        end

        @task.reload
        @task.update!(completed_at: @task.done? ? (@task.completed_at || Time.current) : nil)
      end

      @task
    end

    private

    def normalized_position
      Integer(@attributes.fetch(:position, @task.position))
    rescue ArgumentError, TypeError
      @task.errors.add(:position, "must be an integer")
      raise ActiveRecord::RecordInvalid, @task
    end
  end
end

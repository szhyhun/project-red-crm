module Workflows
  class Runner
    def initialize(run:)
      @run = run
      @workflow = run.board_workflow
      @order = run.order
    end

    def call
      return @run if @run.succeeded? || @run.succeeded_with_warnings?

      @run.update!(status: :running, started_at: Time.current, error: nil)
      warnings = []
      @workflow.actions.ordered.each_with_index do |action, position|
        step = @run.steps.find_or_initialize_by(board_workflow_action: action)
        step.update!(status: :running, position:, input: action.configuration)
        begin
          output = execute(action)
          step.update!(status: output[:skipped] ? :skipped : :succeeded, output: output.except(:skipped))
          warnings << output[:warning] if output[:warning]
        rescue StandardError => error
          step.update!(status: :failed, error: "#{error.class}: #{error.message}")
          @run.update!(status: :failed, error: "#{error.class}: #{error.message}", completed_at: Time.current)
          raise
        end
      end
      @run.update!(status: warnings.compact.empty? ? :succeeded : :succeeded_with_warnings,
                   error: warnings.compact.join("; ").presence, completed_at: Time.current)
      @run
    rescue StandardError => error
      Rails.logger.error("Board workflow run #{@run.id} failed: #{error.class}: #{error.message}")
      @run.reload.update!(status: :failed, error: "#{error.class}: #{error.message}", completed_at: Time.current) unless @run.failed?
      raise
    end

    private

    def matching_deliverables
      @matching_deliverables ||= @order.order_deliverables.active.includes(:service_product, product_component: :package_product).select do |deliverable|
        @workflow.conditions_match?(deliverable)
      end
    end

    def matching_tasks
      matching_deliverables.flat_map(&:workflow_tasks).uniq
    end

    def execute(action)
      case action.action_type
      when "create_parent_task" then create_parent_task(action)
      when "create_or_group_child_task" then create_child_tasks(action)
      when "place_on_board" then place_tasks(action)
      when "link_deliverable" then link_deliverables(action)
      when "assign_to_user" then assign_user(action)
      when "assign_to_group" then assign_group(action)
      else
        { skipped: true, warning: "Unsupported workflow action #{action.action_type}" }
      end
    end

    def create_parent_task(action)
      return { skipped: true, warning: "No listing is available for the parent task" } if @order.listing.blank? && @workflow.board.requires_listing?

      key = "workflow:#{@run.id}:parent"
      task = WorkflowTask.find_or_initialize_by(organization: @order.organization, workflow_group_key: key)
      task.assign_attributes(
        board: @workflow.board,
        listing: @order.listing,
        title: [ action.configuration["title"].presence || "Production", @order.listing&.address ].compact.join(" · "),
        status: first_column_key(@workflow.board),
        task_kind: "parent",
        customer_visible: false,
        metadata: task.metadata.merge("workflow_run_id" => @run.id, "order_id" => @order.id)
      )
      task.save!
      { task_id: task.id }
    end

    def create_child_tasks(action)
      if @order.listing.blank? && @workflow.board.requires_listing?
        return {
          skipped: true,
          warning: "No listing is available for deliverable tasks"
        }
      end

      parent = WorkflowTask.find_by(organization: @order.organization, workflow_group_key: "workflow:#{@run.id}:parent")
      tasks = matching_deliverables.map do |deliverable|
        key = "deliverable:#{deliverable.materialization_key}"
        task = WorkflowTask.find_or_initialize_by(organization: @order.organization, workflow_group_key: key)
        task.assign_attributes(
          board: @workflow.board,
          parent_task: parent,
          listing: deliverable.listing,
          title: deliverable.title,
          description: deliverable.description,
          status: initial_task_status(deliverable),
          task_kind: "deliverable",
          customer_visible: ActiveModel::Type::Boolean.new.cast(action.configuration.fetch("customer_visible", true)),
          metadata: task.metadata.merge("order_deliverable_id" => deliverable.id, "materialization_key" => deliverable.materialization_key)
        )
        task.save!
        task.workflow_task_deliverables.find_or_create_by!(order_deliverable: deliverable, position: deliverable.position)
        task
      end
      { task_ids: tasks.map(&:id), deliverable_ids: matching_deliverables.map(&:id) }
    end

    def place_tasks(action)
      board = resolve_board(action.configuration["board_id"])
      if @order.listing.blank? && board.requires_listing?
        return { skipped: true, warning: "No listing is available for the target board" }
      end

      column = board.workflow_columns.find_by(key: action.configuration["column_key"].presence) || board.workflow_columns.ordered.first
      return { skipped: true, warning: "The workflow has no target column" } if column.blank?

      tasks = matching_tasks
      tasks.each_with_index do |task, index|
        placement = task.workflow_task_placements.find_or_initialize_by(board: board)
        is_home = placement.persisted? ? placement.is_home? : task.home_placement.blank?
        placement.update!(workflow_column: column, position: index, is_home:)
      end
      { board_id: board.id, column_id: column.id, task_ids: tasks.map(&:id) }
    end

    def link_deliverables(_action)
      matching_deliverables.each do |deliverable|
        task = deliverable.workflow_tasks.first
        next if task.blank?

        task.workflow_task_deliverables.find_or_create_by!(order_deliverable: deliverable, position: deliverable.position)
      end
      { deliverable_ids: matching_deliverables.map(&:id), task_ids: matching_tasks.map(&:id) }
    end

    def assign_user(action)
      user = @order.organization.users.active.find_by(id: action.configuration["user_id"])
      return { skipped: true, warning: "The workflow assignee is not an active organization user" } if user.blank?

      matching_tasks.each { |task| task.update!(assignee: user) }
      { user_id: user.id, task_ids: matching_tasks.map(&:id) }
    end

    def assign_group(action)
      group = @order.organization.user_groups.find_by(id: action.configuration["user_group_id"])
      return { skipped: true, warning: "The workflow group is not in this organization" } if group.blank?

      matching_tasks.each { |task| task.update!(metadata: task.metadata.merge("assigned_group_id" => group.id)) }
      { user_group_id: group.id, task_ids: matching_tasks.map(&:id) }
    end

    def resolve_board(id)
      return @workflow.board if id.blank?

      @order.organization.boards.active.find(id)
    end

    def first_column_key(board)
      board.workflow_columns.ordered.first&.key || "todo"
    end

    def initial_task_status(deliverable)
      mapped_column = @workflow.status_mappings.find_by(source_status: deliverable.status)&.target_column_key
      return mapped_column if mapped_column.present? && @workflow.board.workflow_columns.exists?(key: mapped_column)

      first_column_key(@workflow.board)
    end
  end
end

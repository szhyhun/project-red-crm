module Workflows
  # Moves one canonical task through a board placement and synchronizes every
  # related placement and deliverable. This is an application action rather
  # than a model callback because a drag changes several records that must stay
  # in the same state.
  class MoveTask < ApplicationInteractor
    def call
      @task = context.fetch(:task)
      @board = context[:board] || @task.board
      # ActionController::Parameters no longer subclasses Hash, so normalising
      # through to_h keeps this callable with permitted params or a plain hash.
      @attributes = context.fetch(:attributes).to_h.symbolize_keys

      WorkflowTask.transaction { move! }
      context.set(:task, @task)
    rescue ActiveRecord::RecordInvalid => error
      context.fail!(
        code: "workflow_task_move_invalid",
        message: error.record.errors.full_messages.to_sentence,
        original_error: error,
        task_id: @task&.id
      )
    end

    private

    def move!
      selected_placement = placement_for(@board)
      if @board.id != @task.board_id && selected_placement.blank?
        raise ActiveRecord::RecordNotFound, "task is not placed on this board"
      end

      source_status = selected_placement&.workflow_column&.key || @task.status
      target_status = @attributes.fetch(:status, source_status).to_s
      target_column = @board.workflow_columns.find_by(key: target_status)
      unless target_column
        @task.errors.add(:status, "must match a column on this board")
        raise ActiveRecord::RecordInvalid, @task
      end
      target_position = normalized_position
      target_position = [ target_position, 0 ].max

      @task.assign_attributes(@attributes.except(:position, :status, :board_id))
      @task.save!

      reorder_selected_placement!(selected_placement, target_column, target_position) if selected_placement.present? && @board.id != @task.board_id

      # The home board remains the canonical task state. A move made through a
      # shared placement resolves its column by the selected column's
      # customer-facing status, then updates the home card accordingly.
      home_column = @board.id == @task.board_id ? target_column : home_column_for(target_column.canonical_status)
      home_position = if @board.id == @task.board_id
        target_position
      elsif @task.status == home_column.key
        @task.position
      else
        @task.board.workflow_tasks.where(status: home_column.key).count
      end
      reorder_home_task!(home_column, home_position)

      synchronize_shared_placements!(target_column.canonical_status,
                                     skipped_board_ids: [ @task.board_id, @board.id ].uniq)
      synchronize_deliverables!(target_column)
    end

    def normalized_position
      Integer(@attributes.fetch(:position, @task.position))
    rescue ArgumentError, TypeError
      @task.errors.add(:position, "must be an integer")
      raise ActiveRecord::RecordInvalid, @task
    end

    def placement_for(board)
      @task.workflow_task_placements.find_by(board_id: board.id)
    end

    def reorder_selected_placement!(placement, target_column, target_position)
      source_column = placement.workflow_column
      placement.update!(workflow_column: target_column, position: target_position)
      siblings = @board.workflow_task_placements.where(workflow_column: target_column)
        .where.not(id: placement.id).order(:position, :id).to_a
      siblings.insert([ target_position, siblings.length ].min, placement)
      siblings.each_with_index do |sibling, position|
        sibling.update_columns(position:, updated_at: Time.current)
      end

      return if source_column.id == target_column.id

      @board.workflow_task_placements.where(workflow_column: source_column).order(:position, :id)
        .each_with_index { |sibling, position| sibling.update_columns(position:, updated_at: Time.current) }
    end

    def reorder_home_task!(target_column, target_position)
      source_status = @task.status
      @task.status = target_column.key
      @task.save!

      siblings = @task.board.workflow_tasks.where(status: target_column.key).where.not(id: @task.id)
        .order(:position, :id).to_a
      siblings.insert([ target_position, siblings.length ].min, @task)
      siblings.each_with_index do |sibling, position|
        sibling.update_columns(position:, updated_at: Time.current)
      end

      if source_status != target_column.key
        @task.board.workflow_tasks.where(status: source_status).where.not(id: @task.id)
          .order(:position, :id).each_with_index do |sibling, position|
            sibling.update_columns(position:, updated_at: Time.current)
          end
      end

      @task.reload
      @task.workflow_task_placements.find_by(board_id: @task.board_id)&.update!(
        workflow_column: target_column, position: @task.position, updated_at: Time.current
      )
      @task.update!(completed_at: target_column.completed? ? (@task.completed_at || Time.current) : nil)
    end

    def home_column_for(canonical_status)
      columns = @task.board.workflow_columns.ordered.to_a
      columns.find { |column| column.canonical_status == canonical_status } ||
        case canonical_status
        when "not_started" then columns.find { |column| column.key == "todo" }
        when "in_review" then columns.find { |column| column.key == "in_progress" }
        when "delivered" then columns.find(&:completed?)
        when "in_progress" then columns.find { |column| column.key == "in_progress" }
        end || columns.find { |column| column.key == @task.status } || columns.first
    end

    def synchronize_shared_placements!(canonical_status, skipped_board_ids: [])
      placements = @task.workflow_task_placements.includes(board: :workflow_columns).to_a
      placements.each do |placement|
        next if skipped_board_ids.include?(placement.board_id)

        column = placement.board.workflow_columns.find { |entry| entry.canonical_status == canonical_status }
        next if column.blank?

        placement.update!(workflow_column: column, position: next_position(placement.board, column), updated_at: Time.current)
      end
    end

    def synchronize_deliverables!(target_column)
      status = target_column.canonical_status
      @task.order_deliverables.each do |deliverable|
        attributes = { status: status }
        attributes[:delivered_at] = status == "delivered" ? (deliverable.delivered_at || Time.current) : nil
        deliverable.update!(attributes)
        ActivityEvent.create!(organization: deliverable.organization, actor: nil, subject: deliverable,
                              event_type: "order_deliverable.status_changed", payload: {
                                status:,
                                workflow_task_id: @task.id
                              }) if deliverable.saved_change_to_status? && deliverable.status == status
      end
    end

    def next_position(board, column)
      board.workflow_task_placements.where(workflow_column: column).maximum(:position).to_i + 1
    end
  end
end

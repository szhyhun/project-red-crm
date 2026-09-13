class Api::V1::WorkflowTasksController < Api::V1::BaseController
  def self.serialize_comment(comment, capabilities: [], include_replies: true)
    data = comment.slice(:id, :body, :body_html, :parent_comment_id, :created_at, :edited_at).merge(
      author: comment.author.slice(:id, :name, :role),
      capabilities:,
      attachments: comment.board_attachments.order(:created_at, :id).map { |attachment| BoardAttachment.serialize(attachment) }
    )
    return data unless include_replies

    data.merge(
      replies: comment.replies.chronological.includes(:author).map do |reply|
        self.serialize_comment(reply, capabilities: TaskCommentPolicy.new(Current.user, reply).capabilities, include_replies: false)
      end
    )
  end

  def self.serialize_activity(event)
    event.slice(:id, :event_type, :payload, :created_at).merge(
      actor: event.actor&.slice(:id, :name)
    )
  end

  def self.serialize_checklist_item(item)
    item.slice(:id, :title, :position, :completed_at).merge(
      done: item.done?,
      completed_by: item.completed_by&.slice(:id, :name)
    )
  end

  def index
    @requested_board = nil
    if params[:listing_id].present?
      listing = policy_scope(Listing).find(params[:listing_id])
      authorize listing, :view?
      tasks = if current_user.internal?
        policy_scope(WorkflowTask).where(listing_id: listing.id)
      else
        listing.workflow_tasks.where(customer_visible: true)
          .joins(workflow_task_placements: :board)
          .where(boards: { client_visible: true })
          .distinct
      end
      tasks = tasks.includes(
        :assignee, :board, :parent_task, :child_tasks, :board_labels, :task_comments, :task_checklist_items,
        { workflow_task_placements: [ :board, :workflow_column ] },
        order_deliverables: :service_product
      ).order(:position)
    else
      authorize WorkflowTask, :index?
      tasks = policy_scope(WorkflowTask).includes(
        :listing, :assignee, :board, :reporter, :parent_task, :child_tasks, :board_labels,
        :task_comments, :task_checklist_items,
        { workflow_task_placements: [ :board, :workflow_column ] },
        order_deliverables: :service_product
      )
      # Asking for a board you cannot see is a missing board, not an empty one.
      # Filtering by id alone answered 200 with nothing, which reads as "this
      # board exists and is empty" -- resolving through the board scope makes it
      # 404, the same answer every other board route gives.
      if params[:board_id].present?
        @requested_board = policy_scope(Board).find(params[:board_id])
        tasks = tasks.joins(workflow_task_placements: :workflow_column)
          .where(workflow_task_placements: { board_id: @requested_board.id })
          .order("workflow_columns.position ASC", "workflow_task_placements.position ASC", "workflow_task_placements.id ASC")
      else
        tasks = tasks.order(:board_id, :status, :position, :created_at)
      end
    end

    render json: { workflow_tasks: tasks.map { |task| serialize(task) } }
  end

  def show
    task = policy_scope(WorkflowTask).includes(:board, :listing, :assignee, :reporter, :parent_task, :board_labels,
                                               { child_tasks: [
                                                 :listing,
                                                 { workflow_task_placements: [ :board, :workflow_column ] },
                                                 { order_deliverables: :service_product }
                                               ] },
                                               workflow_task_placements: [ :board, :workflow_column ],
                                               order_deliverables: :service_product,
                                               task_comments: :author,
                                               task_checklist_items: :completed_by,
                                               board_attachments: :uploaded_by).find(params[:id])
    authorize task

    render json: { workflow_task: serialize(task, detailed: true) }
  end

  def create
    board = resolve_board
    attributes = task_attributes
    label_values = extract_label_values!(attributes)
    listing = resolve_listing(board, attributes[:listing_id])
    attributes[:status] = board.workflow_columns.ordered.first&.key if attributes[:status].blank?

    task = board.workflow_tasks.build(
      attributes.merge(organization: Current.organization, listing:, reporter: current_user)
    )
    authorize task

    WorkflowTask.transaction do
      task.save!
      assign_labels!(task, label_values)
    end
    record_activity(task, "workflow_task.created")
    render json: { workflow_task: serialize(task.reload) }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def update
    task = policy_scope(WorkflowTask).find(params[:id])
    authorize task

    attributes = task_attributes
    board = resolve_move_board(task, attributes)
    raise Pundit::NotAuthorizedError unless policy(task).update_on_board?(board)
    label_values = extract_label_values!(attributes)
    WorkflowTask.transaction do
      result = Workflows::MoveTask.call(task:, board:, attributes:)
      raise result.failure.original_error || result.failure if result.failure?
      assign_labels!(task, label_values)
    end
    record_activity(task.reload, "workflow_task.updated", status: task.status)
    render json: { workflow_task: serialize(task.reload) }
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def destroy
    task = policy_scope(WorkflowTask).find(params[:id])
    authorize task
    record_activity(task, "workflow_task.deleted")
    task.destroy!
    head :no_content
  end

  private

  # A task can be created from its board or, as before boards existed, from a
  # listing. The listing route resolves to the organization's default board so
  # existing clients keep working unchanged.
  def resolve_board
    return policy_scope(Board).find(params[:board_id]) if params[:board_id].present?

    board = policy_scope(Board).active.ordered.first
    raise ActiveRecord::RecordNotFound, "no board available" if board.blank?

    board
  end

  def resolve_listing(board, attribute_listing_id = nil)
    listing_id = params[:listing_id].presence || attribute_listing_id
    return if listing_id.blank? && !board.requires_listing?

    listing = policy_scope(Listing).find(listing_id) if listing_id.present?
    authorize listing, :update? if listing.present?
    listing
  end

  def resolve_move_board(task, attributes)
    board_id = attributes.delete(:board_id)
    if board_id.blank?
      @requested_board = task.board
      return task.board
    end

    board = policy_scope(Board).find(board_id)
    raise ActiveRecord::RecordNotFound unless task.board_id == board.id || task.workflow_task_placements.exists?(board_id: board.id)

    @requested_board = board
    board
  end

  def task_attributes
    params.require(:workflow_task).permit(
      :title, :description, :status, :assignee_id, :customer_visible,
      :position, :due_at, :priority, :listing_id, :description_html,
      :board_id,
      label_ids: [], labels: []
    ).to_h.symbolize_keys
  end

  def serialize(task, detailed: false)
    placement = placement_for(task)
    column = placement&.workflow_column || columns_by_board_and_key[[ task.board_id, task.status ]]
    board_id = placement&.board_id || task.board_id
    status = placement&.workflow_column&.key || task.status
    data = task.slice(:id, :board_id, :listing_id, :title, :description, :description_html, :status, :priority,
                      :customer_visible, :position, :due_at, :completed_at, :parent_task_id, :task_kind).merge(
      board_id:,
      status:,
      labels: task.board_labels.ordered.map { |label| serialize_label(label) },
      listing_address: task.listing&.address,
      workflow_column_id: column&.id,
      column_category: column&.category,
      placement_id: placement&.id
    )
    return data unless current_user.internal?

    # Board cards show how much detail a task carries without loading it, so
    # the index sends counts and the detail endpoint sends the contents.
    data = data.merge(
      assignee_id: task.assignee_id,
      assignee: task.assignee && task.assignee.slice(:id, :name, :email, :role),
      reporter: task.reporter&.slice(:id, :name),
      comment_count: task.task_comments.size,
      checklist_total: task.task_checklist_items.size,
      checklist_done: task.task_checklist_items.count(&:done?),
      capabilities: capabilities_for(task),
      workflow_placements: visible_placements_for(task).map { |entry| serialize_placement(entry) },
      linked_deliverables: task.order_deliverables.ordered.map { |deliverable| serialize_deliverable_link(deliverable) }
    )
    return data unless detailed

    data.merge(
      comments: task.task_comments.where(parent_comment_id: nil).chronological.map do |comment|
        self.class.serialize_comment(comment, capabilities: capabilities_for(comment))
      end,
      checklist_items: task.task_checklist_items.sort_by { |item| [ item.position, item.id ] }
                           .map { |item| self.class.serialize_checklist_item(item) },
      attachments: task.board_attachments.sort_by { |attachment| [ attachment.created_at, attachment.id ] }
                            .map { |attachment| BoardAttachment.serialize(attachment) },
      activity: activity_for(task),
      child_tasks: task.child_tasks.order(:position, :id).map { |child| serialize_task_summary(child) }
    )
  end

  def serialize_task_summary(task)
    task.slice(:id, :board_id, :listing_id, :parent_task_id, :task_kind, :title, :status, :priority,
               :position, :completed_at).merge(
      listing_address: task.listing&.address,
      workflow_placements: visible_placements_for(task).map { |entry| serialize_placement(entry) },
      linked_deliverables: task.order_deliverables.ordered.map { |deliverable| serialize_deliverable_link(deliverable) }
    )
  end

  def serialize_placement(placement)
    placement.slice(:id, :board_id, :workflow_column_id, :position, :is_home).merge(
      board_name: placement.board&.name,
      column_key: placement.workflow_column&.key,
      column_name: placement.workflow_column&.name
    )
  end

  def serialize_deliverable_link(deliverable)
    deliverable.slice(:id, :title, :deliverable_type, :status, :position).merge(
      service_product: deliverable.service_product&.slice(:id, :title)
    )
  end

  def activity_for(task)
    events = task.activity_events.includes(:actor).order(:created_at, :id)
    return events.map { |event| self.class.serialize_activity(event) } if events.exists?

    [
      {
        id: -task.id,
        event_type: "workflow_task.created",
        payload: {},
        created_at: task.created_at,
        actor: task.reporter&.slice(:id, :name)
      }
    ]
  end

  def columns_by_board_and_key
    @columns_by_board_and_key ||= Current.organization.workflow_columns.index_by { |column| [ column.board_id, column.key ] }
  end

  def placement_for(task)
    if @requested_board.blank?
      placements = visible_placements_for(task)
      return placements.find(&:is_home?) || placements.first
    end

    task.workflow_task_placements.find { |placement| placement.board_id == @requested_board.id }
  end

  def visible_placements_for(task)
    task.workflow_task_placements.ordered.select do |placement|
      BoardPolicy.new(current_user, placement.board).view?
    end
  end

  def record_activity(task, event_type, payload = {})
    ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: task, event_type:, payload:)
  end

  def extract_label_values!(attributes)
    return { ids: attributes.delete(:label_ids) } if attributes.key?(:label_ids)
    return { names: attributes.delete(:labels) } if attributes.key?(:labels)

    nil
  end

  def assign_labels!(task, label_values)
    return if label_values.nil?

    labels = if label_values.key?(:ids)
      label_ids = Array(label_values[:ids]).map do |value|
        Integer(value)
      rescue ArgumentError, TypeError
        -1
      end.uniq
      task.board.board_labels.where(id: label_ids).to_a.tap do |records|
        next if records.size == label_ids.size

        task.errors.add(:labels, "must belong to this board")
        raise ActiveRecord::RecordInvalid, task
      end
    else
      names = Array(label_values[:names]).map { |name| name.to_s.strip }.reject(&:blank?).uniq
      labels_by_name = task.board.board_labels.to_a.index_by { |label| label.name.downcase }
      names.map { |name| labels_by_name[name.downcase] }.tap do |records|
        next if records.compact.size == names.size

        task.errors.add(:labels, "must be selected from this board")
        raise ActiveRecord::RecordInvalid, task
      end.compact
    end

    task.board_labels = labels
  end

  def serialize_label(label)
    Api::V1::BoardLabelsController.serialize_label(label, capabilities: capabilities_for(label))
  end
end

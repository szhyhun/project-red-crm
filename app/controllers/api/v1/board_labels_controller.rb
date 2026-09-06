class Api::V1::BoardLabelsController < Api::V1::BaseController
  before_action :set_board

  def self.serialize_label(label, capabilities: [])
    label.slice(:id, :board_id, :name, :color, :position).merge(
      task_count: label.workflow_tasks.count,
      capabilities:
    )
  end

  def index
    authorize @board, :view?
    labels = policy_scope(BoardLabel).where(board: @board).ordered
    render json: { labels: labels.map { |label| serialize(label) } }
  end

  def create
    attributes = label_params
    label = @board.board_labels.build(attributes)
    label.position = @board.board_labels.maximum(:position).to_i + 1 if attributes[:position].blank?
    authorize label

    if label.save
      render json: { label: serialize(label.reload) }, status: :created
    else
      render_validation_errors(label)
    end
  end

  def update
    label = scoped_labels.find(params[:id])
    authorize label

    if label.update(label_params)
      render json: { label: serialize(label.reload) }
    else
      render_validation_errors(label)
    end
  end

  def destroy
    label = scoped_labels.find(params[:id])
    authorize label
    label.destroy!
    head :no_content
  end

  private

  def set_board
    @board = policy_scope(Board).find(params[:board_id])
  end

  def scoped_labels
    policy_scope(BoardLabel).where(board: @board)
  end

  def label_params
    params.require(:label).permit(:name, :color, :position)
  end

  def serialize(label)
    self.class.serialize_label(label, capabilities: capabilities_for(label))
  end
end

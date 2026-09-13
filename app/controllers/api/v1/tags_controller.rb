class Api::V1::TagsController < Api::V1::BaseController
  def index
    authorize Tag
    tags = policy_scope(Tag).left_joins(:client_account_tags).group(:id).order(:name)
                            .select("tags.*, COUNT(client_account_tags.id) AS team_count")
    render json: { tags: tags.map { |tag| serialize(tag).merge(team_count: tag.team_count) } }
  end

  def create
    tag = Current.organization.tags.build(tag_params)
    authorize tag
    tag.save ? render(json: { tag: serialize(tag) }, status: :created) : render_validation_errors(tag)
  end

  def update
    tag = policy_scope(Tag).find(params[:id])
    authorize tag
    tag.update(tag_params) ? render(json: { tag: serialize(tag) }) : render_validation_errors(tag)
  end

  def destroy
    tag = policy_scope(Tag).find(params[:id])
    authorize tag
    tag.destroy!
    head :no_content
  end

  private

  def tag_params
    params.require(:tag).permit(:name, :color)
  end

  def serialize(tag)
    tag.slice(:id, :name, :color)
  end
end

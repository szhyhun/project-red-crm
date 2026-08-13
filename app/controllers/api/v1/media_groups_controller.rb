class Api::V1::MediaGroupsController < Api::V1::BaseController
  def index
    authorize MediaGroup, :index?
    render json: { media_groups: groups.map { |group| serialize(group) } }
  end

  def create
    group = listing.media_groups.build(group_params.except(:position).merge(organization: Current.organization))
    group.position = normalized_position(group_params[:position], listing.media_groups.count)
    authorize group

    MediaGroup.transaction do
      group.save!
      place!(group, group.position)
    end
    render json: { media_group: serialize(group.reload) }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def update
    group = groups.find(params[:id])
    authorize group
    target_position = normalized_position(group_params[:position], group.position)

    MediaGroup.transaction do
      group.update!(group_params.except(:position))
      place!(group, target_position)
    end
    render json: { media_group: serialize(group.reload) }
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def destroy
    group = groups.find(params[:id])
    authorize group

    # Assets are nullified rather than deleted: dropping a group must never lose
    # media. They reappear in the ungrouped bucket.
    MediaGroup.transaction do
      group.destroy!
      compact_positions!
    end
    head :no_content
  end

  private

  def listing
    @listing ||= policy_scope(Listing).find(params[:listing_id])
  end

  def groups
    listing.media_groups.ordered
  end

  def group_params
    params.require(:media_group).permit(:name, :position, :customer_visible)
  end

  def normalized_position(value, fallback)
    Integer(value.presence || fallback)
  rescue ArgumentError, TypeError
    fallback
  end

  def place!(group, target_position)
    ordered = listing.media_groups.where.not(id: group.id).ordered.to_a
    ordered.insert(target_position.clamp(0, ordered.length), group)
    ordered.each_with_index { |item, position| item.update_columns(position:, updated_at: Time.current) }
  end

  def compact_positions!
    listing.media_groups.ordered.each_with_index do |group, position|
      group.update_columns(position:, updated_at: Time.current)
    end
  end

  def serialize(group)
    group.slice(:id, :listing_id, :name, :position, :customer_visible).merge(
      asset_count: group.media_assets.count
    )
  end
end

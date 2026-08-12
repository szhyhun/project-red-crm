class Api::V1::SavedListingViewsController < Api::V1::BaseController
  def index
    authorize SavedListingView, :index?
    views = policy_scope(SavedListingView).order(:position, :id)
    preference = current_user.listing_view_preference || current_user.build_listing_view_preference
    render json: {
      saved_views: ordered(views, preference.saved_view_order).map { |view| serialize(view) },
      preference: preference.slice(:display_mode, :saved_view_order)
    }
  end

  def create
    view = Current.organization.saved_listing_views.build(view_params.merge(user: current_user))
    authorize view
    view.position = Current.organization.saved_listing_views.maximum(:position).to_i + 1

    if view.save
      render json: { saved_view: serialize(view) }, status: :created
    else
      render_validation_errors(view)
    end
  end

  def update
    view = policy_scope(SavedListingView).find(params[:id])
    authorize view
    return render_validation_errors(view) unless view.update(view_params)

    render json: { saved_view: serialize(view) }
  end

  def destroy
    view = policy_scope(SavedListingView).find(params[:id])
    authorize view
    view.destroy!
    head :no_content
  end

  def preference
    setting = current_user.listing_view_preference || current_user.build_listing_view_preference
    setting.assign_attributes(preference_params)
    return render_validation_errors(setting) unless setting.save

    render json: { preference: setting.slice(:display_mode, :saved_view_order) }
  end

  private

  def view_params
    params.require(:saved_listing_view).permit(:name, :access, filters: {})
  end

  def preference_params
    params.require(:preference).permit(:display_mode, saved_view_order: [])
  end

  def serialize(view)
    view.slice(:id, :name, :access, :filters, :position, :user_id).merge(
      editable: view.user_id == current_user.id,
      owner_name: view.user.name
    )
  end

  def ordered(views, ids)
    positions = Array(ids).map(&:to_i).each_with_index.to_h
    views.sort_by { |view| [ positions.fetch(view.id, positions.size + view.position), view.position, view.id ] }
  end
end

class Api::V1::ListingAssignmentsController < Api::V1::BaseController
  def create
    listing = policy_scope(Listing).find(params[:listing_id])
    authorize listing, :update?
    assignment = listing.listing_assignments.build(assignment_params)

    if assignment.save
      ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: assignment, event_type: "listing_assignment.created")
      render json: { listing_assignment: serialize(assignment) }, status: :created
    else
      render_validation_errors(assignment)
    end
  end

  def destroy
    assignment = ListingAssignment.joins(:listing).merge(policy_scope(Listing)).find(params[:id])
    authorize assignment.listing, :update?
    assignment.destroy!
    head :no_content
  end

  private

  def assignment_params
    params.require(:listing_assignment).permit(:user_id, :role)
  end

  def serialize(assignment)
    assignment.slice(:id, :listing_id, :user_id, :role).merge(user: assignment.user.slice(:id, :name, :role))
  end
end

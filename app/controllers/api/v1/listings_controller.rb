class Api::V1::ListingsController < Api::V1::BaseController
  def index
    listings = policy_scope(Listing).includes(:client_account, :assigned_users).order(created_at: :desc)
    render json: { listings: listings.map { |listing| serialize_listing(listing) } }
  end

  def show
    listing = policy_scope(Listing).includes(:client_account, :workflow_tasks, :appointments, listing_assignments: :user).find(params[:id])
    authorize listing
    render json: { listing: serialize_listing(listing, include_details: true) }
  end

  def create
    listing = Current.organization.listings.build(listing_params)
    authorize listing

    if listing.save
      ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: listing, event_type: "listing.created")
      render json: { listing: serialize_listing(listing) }, status: :created
    else
      render_validation_errors(listing)
    end
  end

  def update
    listing = policy_scope(Listing).find(params[:id])
    authorize listing

    if listing.update(listing_params)
      ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: listing, event_type: "listing.updated")
      render json: { listing: serialize_listing(listing) }
    else
      render_validation_errors(listing)
    end
  end

  private

  def listing_params
    params.require(:listing).permit(
      :client_account_id, :status, :public_slug, :address_line_1, :address_line_2, :city,
      :province, :postal_code, :country, :square_feet, :bedrooms, :bathrooms, :scheduled_at
    )
  end

  def serialize_listing(listing, include_details: false)
    data = {
      id: listing.id,
      status: listing.status,
      address: listing.address,
      square_feet: listing.square_feet,
      scheduled_at: listing.scheduled_at,
      client_account: { id: listing.client_account.id, name: listing.client_account.name }
    }
    return data unless include_details

    tasks = listing.workflow_tasks.includes(:assignee).order(:position)
    tasks = tasks.where(customer_visible: true) unless current_user.internal?
    return data.merge(workflow_tasks: tasks.map { |task| serialize_task(task) }, appointments: [], assignments: []) unless current_user.internal?

    data.merge(
      workflow_tasks: tasks.map { |task| serialize_task(task) },
      appointments: listing.appointments.includes(:assigned_user).order(:starts_at).map { |appointment| serialize_appointment(appointment) },
      assignments: listing.listing_assignments.map { |assignment| serialize_assignment(assignment) }
    )
  end

  def serialize_task(task)
    { id: task.id, title: task.title, status: task.status, stage: task.stage, assignee_id: task.assignee_id,
      customer_visible: task.customer_visible, due_at: task.due_at, assignee: task.assignee && task.assignee.slice(:id, :name, :role) }
  end

  def serialize_appointment(appointment)
    appointment.slice(:id, :status, :starts_at, :ends_at, :notes).merge(
      assigned_user: appointment.assigned_user && appointment.assigned_user.slice(:id, :name, :role)
    )
  end

  def serialize_assignment(assignment)
    assignment.slice(:id, :user_id, :role).merge(user: assignment.user.slice(:id, :name, :role))
  end
end

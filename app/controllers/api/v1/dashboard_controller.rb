class Api::V1::DashboardController < Api::V1::BaseController
  def show
    render json: {
      listings: {
        active: Current.organization.listings.where.not(status: %w[delivered cancelled]).count,
        awaiting_review: Current.organization.listings.review.count
      },
      tasks: {
        mine: Current.organization.workflow_tasks.where(assignee: current_user).where.not(status: :done).count,
        blocked: Current.organization.workflow_tasks.blocked.count
      },
      appointments: Current.organization.appointments.where("starts_at >= ?", Time.current).order(:starts_at).limit(5).map do |appointment|
        { id: appointment.id, listing_id: appointment.listing_id, starts_at: appointment.starts_at, ends_at: appointment.ends_at,
          status: appointment.status, address: appointment.listing.address }
      end
    }
  end
end

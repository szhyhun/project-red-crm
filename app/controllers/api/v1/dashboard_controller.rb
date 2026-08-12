class Api::V1::DashboardController < Api::V1::BaseController
  def show
    return render json: { error: "forbidden" }, status: :forbidden unless current_user.internal?

    completed_statuses = Current.organization.workflow_columns.completed.pluck(:key)
    blocked_statuses = Current.organization.workflow_columns.blocked.pluck(:key)

    render json: {
      listings: {
        active: Current.organization.listings.where.not(status: %w[delivered cancelled]).count,
        awaiting_review: Current.organization.listings.review.count
      },
      tasks: {
        mine: Current.organization.workflow_tasks.where(assignee: current_user).where.not(status: completed_statuses).count,
        blocked: Current.organization.workflow_tasks.where(status: blocked_statuses).count
      },
      feedback: feedback_metrics,
      delivery: delivery_metrics,
      appointments: upcoming_appointments.map do |appointment|
        { id: appointment.id, listing_id: appointment.listing_id, starts_at: appointment.starts_at, ends_at: appointment.ends_at,
          status: appointment.status, address: appointment.listing.address, notes: appointment.notes,
          assigned_user: appointment.assigned_user&.slice(:id, :name, :email, :role) }
      end
    }
  end

  private

  def feedback_metrics
    feedbacks = Current.organization.listing_feedbacks.includes(:listing, :client_account)
    submitted = feedbacks.select(&:submitted_at?)
    ratings = submitted.flat_map { |feedback| [feedback.delivery_rating, feedback.service_rating, feedback.media_rating].compact }

    {
      total: feedbacks.length,
      submitted: submitted.length,
      needs_attention: feedbacks.count { |feedback| feedback.follow_up_status_needed? },
      average_rating: ratings.empty? ? nil : (ratings.sum.to_f / ratings.length).round(2),
      recent_needs_attention: feedbacks.select { |feedback| feedback.follow_up_status_needed? }
        .sort_by { |feedback| -feedback.created_at.to_i }
        .first(5)
        .map do |feedback|
          {
            id: feedback.id,
            listing_id: feedback.listing_id,
            listing_address: feedback.listing.address,
            client_name: feedback.client_account.name,
            average_rating: feedback_average(feedback),
            comment: feedback.comment,
            created_at: feedback.created_at
          }
        end
    }
  end

  def delivery_metrics
    delivered = Current.organization.listings.where(delivery_status: :delivered).where.not(delivered_at: nil).includes(:appointments)
    turnaround_hours = delivered.filter_map do |listing|
      completed_at = listing.appointments.filter_map(&:completed_at).max
      next if completed_at.blank?

      ((listing.delivered_at - completed_at) / 1.hour).round(2)
    end

    {
      delivered: delivered.length,
      measured: turnaround_hours.length,
      average_hours: turnaround_hours.empty? ? nil : (turnaround_hours.sum / turnaround_hours.length).round(2),
      late: turnaround_hours.count { |hours| hours > 48 },
      distribution: {
        under_24: turnaround_hours.count { |hours| hours <= 24 },
        under_48: turnaround_hours.count { |hours| hours > 24 && hours <= 48 },
        under_72: turnaround_hours.count { |hours| hours > 48 && hours <= 72 },
        over_72: turnaround_hours.count { |hours| hours > 72 }
      }
    }
  end

  def feedback_average(feedback)
    ratings = [feedback.delivery_rating, feedback.service_rating, feedback.media_rating].compact
    ratings.empty? ? nil : (ratings.sum.to_f / ratings.length).round(2)
  end

  def upcoming_appointments
    Current.organization.appointments
           .includes(:listing, :assigned_user)
           .where("starts_at >= ?", Time.current)
           .order(:starts_at)
           .limit(5)
  end
end

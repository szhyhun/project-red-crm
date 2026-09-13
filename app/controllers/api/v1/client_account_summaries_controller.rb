class Api::V1::ClientAccountSummariesController < Api::V1::BaseController
  ACTIVITY_LIMIT = 50

  # The numbers across the top of a team page, and what happened to the team
  # and the people in it, newest first.
  def show
    account = policy_scope(ClientAccount).find(params[:client_account_id])
    authorize account, :view?
    memberships = account.client_memberships.active

    render json: {
      summary: {
        client_account_id: account.id,
        listings_count: account.listings.count,
        orders_count: account.orders.count,
        members_count: memberships.count,
        admins_count: memberships.admin.count,
        invited_count: account.client_memberships.invited.count,
        activity: user_can_read_activity?(account) ? activity_for(account) : []
      }
    }
  end

  private

  def user_can_read_activity?(account)
    current_user.internal? || ClientAccountPolicy.new(current_user, account).manage?
  end

  def activity_for(account)
    events = ActivityEvent.where(organization: account.organization)
      .where(subject: account)
      .or(ActivityEvent.where(organization: account.organization, subject_type: "ClientMembership")
                       .where("activity_events.payload ->> 'client_account_id' = ?", account.id.to_s))
      .includes(:actor).order(created_at: :desc, id: :desc).limit(ACTIVITY_LIMIT)

    events.map do |event|
      event.slice(:id, :event_type, :subject_type, :subject_id, :payload, :created_at).merge(actor: event.actor&.slice(:id, :name))
    end
  end
end

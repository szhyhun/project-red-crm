class Api::V1::ClientAccountArchivesController < Api::V1::BaseController
  # Archiving is one field and one audit line, so it stays a controller action.
  def create
    change(archived_at: Time.current, event_type: "client_account.archived")
  end

  def destroy
    change(archived_at: nil, event_type: "client_account.restored")
  end

  private

  def change(archived_at:, event_type:)
    account = policy_scope(ClientAccount).find(params[:client_account_id])
    authorize account, :archive?
    account.update!(archived_at:)
    ActivityEvent.create!(organization: account.organization, actor: current_user, subject: account, event_type:)

    render json: { client_account: account.slice(:id, :archived_at) }
  end
end

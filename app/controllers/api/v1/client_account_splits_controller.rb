class Api::V1::ClientAccountSplitsController < Api::V1::BaseController
  def create
    account = policy_scope(ClientAccount).find(params[:client_account_id])
    authorize account, :split?
    result = ClientAccounts::Split.call(account:, actor: current_user, name: split_params[:name],
                                        membership_ids: split_params[:membership_ids])
    if result.failure?
      return render_validation_errors(result.failure.original_error.record) if result.failure.original_error

      return render json: { error: result.failure.code, details: { base: [ result.failure.message ] } }, status: :unprocessable_content
    end

    team = result.fetch(:team)
    render json: { client_account: team.slice(:id, :name, :kind) }, status: :created
  end

  private

  def split_params
    params.require(:split).permit(:name, membership_ids: [])
  end
end

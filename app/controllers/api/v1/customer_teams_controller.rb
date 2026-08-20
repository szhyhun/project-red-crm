class Api::V1::CustomerTeamsController < Api::V1::BaseController
  def index
    authorize CustomerTeam, :index?
    teams = policy_scope(CustomerTeam).includes(customer_team_memberships: :client_account).order(:name)
    render json: { customer_teams: teams.map { |team| serialize(team) } }
  end

  def create
    team = Current.organization.customer_teams.build(customer_team_params)
    authorize team
    team.save!
    render json: { customer_team: serialize(team) }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def update
    team = policy_scope(CustomerTeam).find(params[:id])
    authorize team
    team.update!(customer_team_params)
    render json: { customer_team: serialize(team) }
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def destroy
    team = policy_scope(CustomerTeam).find(params[:id])
    authorize team
    team.destroy!
    head :no_content
  end

  private

  def customer_team_params
    params.require(:customer_team).permit(:name, :brokerage_name, :brokerage_website, :website, :logo_url, :description, :archived)
  end

  def serialize(team)
    team.slice(:id, :name, :brokerage_name, :brokerage_website, :website, :logo_url, :description, :archived).merge(
      client_accounts: team.customer_team_memberships.map do |membership|
        membership.client_account.slice(:id, :name, :email, :brokerage_name).merge(primary: membership.primary)
      end
    )
  end
end

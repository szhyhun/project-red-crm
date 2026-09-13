class Api::V1::CustomerUsersController < Api::V1::BaseController
  SOCIAL_PROFILE_KEYS = %i[website facebook instagram linkedin twitter zillow].freeze

  def index
    authorize User, :index?, policy_class: CustomerUserPolicy
    people = customer_scope.includes(client_memberships: :client_account).order(:name).to_a
    overrides = PricingPlan.where(user_id: people.map(&:id)).pluck(:user_id, :id).to_h

    render json: { customer_users: people.map { |person| serialize(person, overrides[person.id]) } }
  end

  def show
    person = customer_scope.includes(client_memberships: :client_account).find(params[:id])
    authorize person, :view?, policy_class: CustomerUserPolicy

    render json: { customer_user: serialize(person, PricingPlan.where(user: person).pick(:id)) }
  end

  # A plain record edit: no other record has to agree with it, so it stays in
  # the controller rather than becoming an Interactor.
  def update
    person = customer_scope.find(params[:id])
    authorize person, :update?, policy_class: CustomerUserPolicy

    if person.update(update_params)
      ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: person,
                            event_type: "customer_user.updated", payload: { changed: person.previous_changes.keys - %w[updated_at] })
      render json: { customer_user: serialize(person.reload, PricingPlan.where(user: person).pick(:id)) }
    else
      render_validation_errors(person)
    end
  end

  private

  def customer_scope
    policy_scope(User, policy_scope_class: CustomerUserPolicy::Scope)
  end

  def update_params
    params.require(:customer_user).permit(
      :name, :phone, :license_number, :avatar_url, :timezone, :internal_note,
      :blocked_from_ordering, :credit_balance_cents, social_profiles: SOCIAL_PROFILE_KEYS
    )
  end

  def serialize(person, pricing_plan_id)
    memberships = person.client_memberships.sort_by { |membership| [ membership.created_at, membership.id ] }
    person.slice(:id, :name, :email, :phone, :license_number, :avatar_url, :timezone, :internal_note,
                 :social_profiles, :blocked_from_ordering, :credit_balance_cents, :created_at).merge(
      invitation_pending: person.invitation_sent_at.present? && person.invitation_accepted_at.blank?,
      team_count: memberships.count(&:active?),
      pricing_plan_id:,
      teams: memberships.map do |membership|
        membership.slice(:id, :role, :status, :is_default, :invitation_accepted_at).merge(
          client_account: membership.client_account.slice(:id, :name, :kind)
        )
      end
    )
  end
end

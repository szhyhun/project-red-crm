class Api::V1::CustomerUsersController < Api::V1::BaseController
  SOCIAL_PROFILE_KEYS = %i[website facebook instagram linkedin twitter zillow].freeze

  def index
    authorize User, :index?, policy_class: CustomerUserPolicy
    people = customer_scope.includes(client_memberships: :client_account).order(:name).to_a
    overrides = PricingPlan.where(user_id: people.map(&:id)).pluck(:user_id, :id).to_h
    @work_counts = WorkCounts.new(people)

    render json: { customer_users: people.map { |person| serialize(person, overrides[person.id]) } }
  end

  def show
    person = customer_scope.includes(client_memberships: :client_account).find(params[:id])
    authorize person, :view?, policy_class: CustomerUserPolicy

    @work_counts = WorkCounts.new([ person ])
    render json: { customer_user: serialize(person, PricingPlan.where(user: person).pick(:id)) }
  end

  # The listings this person booked and the orders they placed, across teams.
  def work
    person = customer_scope.find(params[:id])
    authorize person, :view?, policy_class: CustomerUserPolicy
    listings = Listing.where(organization: Current.organization, booked_by: person).includes(:client_account)
                      .order(created_at: :desc).limit(100)
    orders = Order.where(organization: Current.organization, ordered_by: person).includes(:client_account, :listing)
                  .order(created_at: :desc).limit(100)

    render json: {
      listings: listings.map { |listing| listing.slice(:id, :status, :created_at).merge(address: listing.address, client_account: listing.client_account.slice(:id, :name)) },
      orders: orders.map do |order|
        order.slice(:id, :status, :total_cents, :credit_applied_cents, :created_at)
             .merge(client_account: order.client_account.slice(:id, :name), listing_address: order.listing&.address)
      end
    }
  end

  # A plain record edit: no other record has to agree with it, so it stays in
  # the controller rather than becoming an Interactor.
  def update
    person = customer_scope.find(params[:id])
    authorize person, :update?, policy_class: CustomerUserPolicy

    @work_counts = WorkCounts.new([ person ])
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
      :blocked_from_ordering, social_profiles: SOCIAL_PROFILE_KEYS
    )
  end

  def serialize(person, pricing_plan_id)
    memberships = person.client_memberships.sort_by { |membership| [ membership.created_at, membership.id ] }
    person.slice(:id, :name, :email, :phone, :license_number, :avatar_url, :timezone, :internal_note,
                 :social_profiles, :blocked_from_ordering, :credit_balance_cents, :created_at).merge(
      invitation_pending: person.invitation_sent_at.present? && person.invitation_accepted_at.blank?,
      team_count: memberships.count(&:active?),
      pricing_plan_id:,
      capabilities: CustomerUserPolicy.new(current_user, person).capabilities,
      teams: memberships.map do |membership|
        account_id = membership.client_account_id
        membership.slice(:id, :role, :status, :is_default, :invitation_accepted_at, :created_at).merge(
          client_account: membership.client_account.slice(:id, :name, :kind, :archived_at).merge(
            member_count: @work_counts.members(account_id)
          ),
          listings_count: @work_counts.listings(person.id, account_id),
          team_listings_count: @work_counts.team_listings(account_id),
          orders_count: @work_counts.orders(person.id, account_id),
          team_orders_count: @work_counts.team_orders(account_id)
        )
      end
    )
  end

  # "2 listings / 5 team listings" for every membership shown, in a handful of
  # grouped queries rather than four per row.
  class WorkCounts
    def initialize(people)
      account_ids = people.flat_map { |person| person.client_memberships.map(&:client_account_id) }.uniq
      user_ids = people.map(&:id)
      @team_listings = Listing.where(client_account_id: account_ids).group(:client_account_id).count
      @team_orders = Order.where(client_account_id: account_ids).group(:client_account_id).count
      @listings = Listing.where(client_account_id: account_ids, booked_by_id: user_ids).group(:booked_by_id, :client_account_id).count
      @orders = Order.where(client_account_id: account_ids, ordered_by_id: user_ids).group(:ordered_by_id, :client_account_id).count
      @members = ClientMembership.active.where(client_account_id: account_ids).group(:client_account_id).count
    end

    def team_listings(account_id) = @team_listings.fetch(account_id, 0)
    def team_orders(account_id) = @team_orders.fetch(account_id, 0)
    def listings(user_id, account_id) = @listings.fetch([ user_id, account_id ], 0)
    def orders(user_id, account_id) = @orders.fetch([ user_id, account_id ], 0)
    def members(account_id) = @members.fetch(account_id, 0)
  end
end

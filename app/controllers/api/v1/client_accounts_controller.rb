class Api::V1::ClientAccountsController < Api::V1::BaseController
  def index
    accounts = policy_scope(ClientAccount).includes(
      :tags, :billing_user, :client_memberships, listing_feedbacks: :listing
    ).order(:name)
    accounts = accounts.where(id: ClientAccountTag.where(tag_id: params[:tag_id]).select(:client_account_id)) if params[:tag_id].present?
    render json: { client_accounts: accounts.map { |account| serialize(account) } }
  end

  def create
    account = Current.organization.client_accounts.build(client_account_params)
    authorize account

    if account.save
      render json: { client_account: serialize(account) }, status: :created
    else
      render_validation_errors(account)
    end
  end

  def update
    account = policy_scope(ClientAccount).find(params[:id])
    authorize account

    if account.update(client_account_params)
      render json: { client_account: serialize(account) }
    else
      render_validation_errors(account)
    end
  end

  def billing
    account = policy_scope(ClientAccount).find(params[:id])
    authorize account, :configure_billing?
    result = ClientAccounts::ConfigureBilling.call(account:, actor: current_user, attributes: billing_params)
    raise result.failure.original_error || result.failure if result.failure?

    render json: { client_account: serialize(result.fetch(:account)) }
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  # Kept for older clients. The membership it creates is an invitation like any
  # other, so access begins when the person accepts rather than when we add them.
  def invite
    account = policy_scope(ClientAccount).find(params[:id])
    authorize account, :invite?
    result = ClientMemberships::Invite.call(
      account:, actor: current_user, email: invite_params[:email], name: invite_params[:name],
      role: invite_params[:membership_role]
    )
    raise result.failure.original_error || result.failure if result.failure?
    membership = result.fetch(:membership)

    render json: { client_user: membership.user.slice(:id, :name, :email, :role) }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  private

  def client_account_params
    params.require(:client_account).permit(
      :name, :kind, :email, :phone, :brokerage_name, :brokerage_website, :website, :logo_url,
      :description, :internal_note, :affiliate_id, :archived_at,
      :lock_downloads_before_payment, :display_original_price, :suppress_payment_reminders, :order_form_id,
      :member_listing_access
    )
  end

  def billing_params
    params.require(:client_account).permit(*ClientAccounts::ConfigureBilling::ATTRIBUTES)
  end

  def invite_params
    params.require(:client_user).permit(:name, :email, :membership_role).tap do |attributes|
      attributes[:role] = attributes[:membership_role] == "member" ? "client_member" : "client_admin"
      attributes[:membership_role] = "admin" unless %w[admin member].include?(attributes[:membership_role])
    end
  end

  def serialize(account)
    feedbacks = if account.association(:listing_feedbacks).loaded?
      account.listing_feedbacks.sort_by { |feedback| [ -feedback.created_at.to_f, -feedback.id ] }
    else
      account.listing_feedbacks.includes(:listing).order(created_at: :desc).to_a
    end
    submitted = feedbacks.select(&:submitted_at?)
    ratings = submitted.flat_map { |feedback| [ feedback.delivery_rating, feedback.service_rating, feedback.media_rating ].compact }

    account.slice(:id, :name, :kind, :email, :phone, :brokerage_name, :brokerage_website, :website,
                  :logo_url, :description, :internal_note, :affiliate_id, :archived_at,
                  :lock_downloads_before_payment, :display_original_price, :suppress_payment_reminders,
                  :order_form_id, :member_listing_access, :billing_user_id, :billing_pays_externally, :billing_visibility, :pricing_visibility,
                  :downloads_visibility, :marketing_templates_visibility).merge(
      billing_user: account.billing_user&.slice(:id, :name, :email),
      tags: current_user.internal? ? account.tags.sort_by(&:name).map { |tag| tag.slice(:id, :name, :color) } : [],
      member_count: if account.association(:client_memberships).loaded?
                       account.client_memberships.count(&:active?)
                    else
                       account.client_memberships.active.count
                    end,
      capabilities: ClientAccountPolicy.new(current_user, account).capabilities,
      feedback_summary: {
        total: feedbacks.length,
        submitted: submitted.length,
        needs_attention: feedbacks.count { |feedback| feedback.follow_up_status_needed? },
        average_rating: ratings.empty? ? nil : (ratings.sum.to_f / ratings.length).round(2),
        latest_submitted_at: submitted.first&.submitted_at
      },
      feedback_history: feedbacks.first(20).map do |feedback|
        {
          id: feedback.id,
          listing_id: feedback.listing_id,
          listing_address: feedback.listing.address,
          delivery_rating: feedback.delivery_rating,
          service_rating: feedback.service_rating,
          media_rating: feedback.media_rating,
          follow_up_status: feedback.follow_up_status,
          comment: feedback.comment,
          submitted_at: feedback.submitted_at,
          created_at: feedback.created_at
        }
      end
    )
  end
end

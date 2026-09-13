class Api::V1::CreditTransactionsController < Api::V1::BaseController
  def index
    person = customer
    authorize person, :view?, policy_class: CustomerUserPolicy
    entries = CreditTransaction.where(user: person).includes(:actor).order(created_at: :desc, id: :desc).limit(100)

    render json: { credit_transactions: entries.map { |entry| serialize(entry) } }
  end

  def create
    person = customer
    authorize person, :update?, policy_class: CustomerUserPolicy
    result = CustomerUsers::AdjustCredit.call(
      person:, actor: current_user, amount_cents: credit_params[:amount_cents], reason: credit_params[:reason]
    )
    if result.failure?
      return render_validation_errors(result.failure.original_error.record) if result.failure.original_error

      return render json: { error: result.failure.code, details: { base: [ result.failure.message ] } }, status: :unprocessable_content
    end

    render json: { credit_transaction: serialize(result.fetch(:credit_transaction)), credit_balance_cents: person.reload.credit_balance_cents },
           status: :created
  end

  private

  def customer
    policy_scope(User, policy_scope_class: CustomerUserPolicy::Scope).find(params[:customer_user_id])
  end

  def credit_params
    params.require(:credit_transaction).permit(:amount_cents, :reason)
  end

  def serialize(entry)
    entry.slice(:id, :amount_cents, :balance_after_cents, :reason, :order_id, :created_at)
         .merge(actor: entry.actor&.slice(:id, :name))
  end
end

module CustomerUsers
  # Grants or takes back a person's credit. The balance and the ledger row that
  # explains it change together, under a lock, so two adjustments at once cannot
  # both read the same starting balance.
  class AdjustCredit < ApplicationInteractor
    def call
      person = context.fetch(:person)
      actor = context[:actor]
      amount_cents = Integer(context.fetch(:amount_cents), exception: false)
      reason = context.fetch(:reason).to_s.strip

      transaction = User.transaction do
        person.lock!
        balance = person.credit_balance_cents + amount_cents.to_i
        if balance.negative?
          context.fail!(code: "credit_balance_negative", message: "Credit cannot go below zero; this person has #{person.credit_balance_cents} cents")
        end

        entry = CreditTransaction.create!(
          organization: person.organization, user: person, actor:, order: context[:order],
          amount_cents:, balance_after_cents: balance, reason:
        )
        person.update!(credit_balance_cents: balance)
        ActivityEvent.create!(organization: person.organization, actor:, subject: person, event_type: "customer_user.credit_adjusted",
                              payload: { amount_cents:, balance_after_cents: balance, credit_transaction_id: entry.id })
        entry
      end

      context.set(:credit_transaction, transaction)
    rescue ActiveRecord::RecordInvalid => error
      context.fail!(
        code: "credit_adjustment_invalid",
        message: error.record.errors.full_messages.to_sentence,
        original_error: error,
        user_id: context[:person]&.id
      )
    end
  end
end

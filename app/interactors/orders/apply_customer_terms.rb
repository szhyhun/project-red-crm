module Orders
  # The terms a team sets for paying, applied to a new order: whose credit it
  # spends, and whether anyone is asked to pay when it is placed. A team with a
  # billing member charges that member, so the person ordering is not asked to
  # pay up front; a team that settles outside the system is never asked.
  class ApplyCustomerTerms < ApplicationInteractor
    def call
      order = context.fetch(:order)
      ordered_by = context[:ordered_by]
      account = order.client_account
      customer = ordered_by if ordered_by.present? && !ordered_by.internal?

      order.payment_mode = :pay_later if account.billing_pays_externally? || (account.billing_user_id.present? && customer && customer.id != account.billing_user_id)
      apply_credit(order, payer_for(account, customer), actor: ordered_by)
      order.save! if order.changed?

      context.set(:order, order)
    end

    private

    def payer_for(account, customer)
      return nil if account.billing_pays_externally?

      account.billing_user || customer
    end

    def apply_credit(order, payer, actor:)
      return if payer.blank? || order.credit_applied_cents.positive?

      amount = [ payer.reload.credit_balance_cents, order.total_cents ].min
      return unless amount.positive?

      result = CustomerUsers::AdjustCredit.call(person: payer, actor:, order:, amount_cents: -amount,
                                                reason: "Applied to order ##{order.id}")
      raise result.failure.original_error || result.failure if result.failure?

      order.credit_applied_cents = amount
      order.recalculate_totals!
    end
  end
end

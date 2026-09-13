module Orders
  # Keeps the credit an order spent no larger than what the order now costs.
  # When items are removed, a discount grows, or the order is cancelled, the
  # difference goes back to the person whose credit it was, in their ledger.
  class RebalanceCredit < ApplicationInteractor
    def call
      order = context.fetch(:order)
      return context if order.credit_applied_cents.zero?

      gross = [ order.subtotal_cents - order.discount_cents + order.tax_cents + order.fee_cents, 0 ].max
      keep = order.cancelled? ? 0 : [ order.credit_applied_cents, gross ].min
      refund = order.credit_applied_cents - keep
      return context unless refund.positive?

      payer = CreditTransaction.where(order:).where("amount_cents < 0").order(:id).first&.user
      return context if payer.blank?

      Order.transaction do
        result = CustomerUsers::AdjustCredit.call(person: payer, actor: context[:actor], order:, amount_cents: refund,
                                                  reason: "Returned from order ##{order.id}")
        raise result.failure.original_error || result.failure if result.failure?

        order.credit_applied_cents = keep
        order.recalculate_totals!
        order.save!
      end
      context.set(:refunded_cents, refund)
    end
  end
end

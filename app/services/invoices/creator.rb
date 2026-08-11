module Invoices
  class Creator
    def initialize(organization:, order:)
      @organization = organization
      @order = order
    end

    def create!
      return @order.invoices.first if @order.invoices.exists?

      @organization.with_lock do
        return @order.invoices.first if @order.invoices.exists?

        invoice = @organization.invoices.create!(
          client_account: @order.client_account,
          listing: @order.listing,
          order: @order,
          number: next_number,
          currency: @order.currency,
          subtotal_cents: @order.subtotal_cents,
          tax_cents: @order.tax_cents,
          total_cents: @order.total_cents,
          balance_due_cents: @order.total_cents
        )
        @order.update!(status: :invoiced) unless @order.invoiced?
        invoice
      end
    end

    private

    def next_number
      sequence = @organization.invoices.maximum(:id).to_i + 1
      format("PR-%06d", sequence)
    end
  end
end

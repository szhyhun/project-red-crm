module Orders
  class Creator
    def initialize(organization:, attributes:)
      @organization = organization
      @attributes = attributes
    end

    def create!
      Order.transaction do
        client_account = @organization.client_accounts.find(@attributes.fetch(:client_account_id))
        listing = @attributes[:listing_id].present? ? @organization.listings.find(@attributes[:listing_id]) : nil
        order = @organization.orders.build(
          client_account: client_account,
          listing: listing,
          payment_mode: @attributes.fetch(:payment_mode, "pay_later"),
          currency: @attributes.fetch(:currency, "cad"),
          discount_cents: @attributes.fetch(:discount_cents, 0),
          tax_cents: @attributes.fetch(:tax_cents, 0)
        )

        @attributes.fetch(:items).each do |item_input|
          item_input = item_input.symbolize_keys
          variant = find_variant(item_input.fetch(:product_variant_id))
          quantity = Integer(item_input.fetch(:quantity, 1))

          order.order_items.build(
            product: variant.product,
            product_variant: variant,
            title: [variant.product.title, variant.title].compact.join(" - "),
            quantity: quantity,
            unit_price_cents: variant.price_cents,
            total_cents: variant.price_cents * quantity,
            snapshot: {
              product_title: variant.product.title,
              variant_title: variant.title,
              price_cents: variant.price_cents
            }
          )
        end

        order.recalculate_totals!
        order.save!
        order
      end
    end

    private

    def find_variant(id)
      ProductVariant.joins(:product)
                    .where(products: { organization_id: @organization.id, active: true })
                    .active
                    .find(id)
    end
  end
end

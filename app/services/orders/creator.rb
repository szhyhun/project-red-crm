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
          discount_type: @attributes.fetch(:discount_type, "fixed"),
          discount_cents: @attributes.fetch(:discount_cents, 0),
          discount_rate_basis_points: @attributes.fetch(:discount_rate_basis_points, 0),
          fee_cents: @attributes.fetch(:fee_cents, 0),
          fee_label: @attributes.fetch(:fee_label, "Service fee"),
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
        record_activity(order, "order.created")
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

    def record_activity(order, event_type)
      return unless order.listing

      ActivityEvent.create!(organization: @organization, actor: nil, subject: order, event_type: event_type,
                            payload: {
                              listing_id: order.listing_id,
                              order_id: order.id,
                              order_item_ids: order.order_items.ids,
                              total_cents: order.total_cents,
                              payment_mode: order.payment_mode
                            })
      ActivityEvent.create!(organization: @organization, actor: nil, subject: order.listing, event_type: event_type,
                            payload: {
                              order_id: order.id,
                              order_item_ids: order.order_items.ids,
                              total_cents: order.total_cents,
                              payment_mode: order.payment_mode
                            })
    end
  end
end

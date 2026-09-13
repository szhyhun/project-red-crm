module Orders
  # Creates an order, snapshots the effective catalog price, and records the
  # customer-facing activity as one business action. Pricing resolution remains
  # a service because it is a read-side rule used by this action.
  class Create < ApplicationInteractor
    def call
      @organization = context.fetch(:organization)
      @attributes = context.fetch(:attributes).to_h.symbolize_keys
      @ordered_by = context[:ordered_by]

      order = Order.transaction do
        client_account = @organization.client_accounts.find(@attributes.fetch(:client_account_id))
        refuse_blocked_customer!(client_account)
        listing = @attributes[:listing_id].present? ? @organization.listings.find(@attributes[:listing_id]) : nil
        order = build_order(client_account:, listing:)

        @attributes.fetch(:items).each { |item_input| add_item!(order, client_account, item_input) }

        order.recalculate_totals!
        order.save!
        order = apply_customer_terms(order)
        record_activity(order)
        order
      end

      context.set(:order, order)
    rescue ActiveRecord::RecordInvalid => error
      context.fail!(
        code: "order_create_invalid",
        message: error.record.errors.full_messages.to_sentence,
        original_error: error,
        organization_id: context[:organization]&.id
      )
    end

    private

    # Whose credit the order spends and whether anyone pays up front are the
    # team's terms, settled before the order is announced.
    def apply_customer_terms(order)
      result = Orders::ApplyCustomerTerms.call(order:, ordered_by: @ordered_by)
      raise result.failure.original_error || result.failure if result.failure?

      result.fetch(:order)
    end

    def build_order(client_account:, listing:)
      @organization.orders.build(
        client_account:,
        listing:,
        ordered_by: @ordered_by,
        payment_mode: @attributes.fetch(:payment_mode, "pay_later"),
        currency: @attributes.fetch(:currency, "cad"),
        discount_type: @attributes.fetch(:discount_type, "fixed"),
        discount_cents: @attributes.fetch(:discount_cents, 0),
        discount_rate_basis_points: @attributes.fetch(:discount_rate_basis_points, 0),
        fee_cents: @attributes.fetch(:fee_cents, 0),
        fee_label: @attributes.fetch(:fee_label, "Service fee"),
        tax_cents: @attributes.fetch(:tax_cents, 0)
      )
    end

    def add_item!(order, client_account, item_input)
      item_input = item_input.symbolize_keys
      variant = find_variant(item_input.fetch(:product_variant_id))
      quantity = Integer(item_input.fetch(:quantity, 1))
      price_cents = PricingPlans::Resolver.new(client_account:, product_variant: variant, user: @ordered_by).price_cents

      order.order_items.build(
        product: variant.product,
        product_variant: variant,
        title: [ variant.product.title, variant.title ].compact.join(" - "),
        quantity:,
        unit_price_cents: price_cents,
        total_cents: price_cents * quantity,
        snapshot: OrderItem.catalog_snapshot(variant, price_cents:)
      )
    end

    # Blocking someone from ordering has to refuse the order, not colour a row.
    def refuse_blocked_customer!(client_account)
      return if @ordered_by.blank? || @ordered_by.internal?
      return unless @ordered_by.blocked_from_ordering?

      order = @organization.orders.build(client_account:)
      order.errors.add(:base, "This customer cannot place orders")
      raise ActiveRecord::RecordInvalid, order
    end

    def find_variant(id)
      ProductVariant.joins(:product)
                    .where(products: { organization_id: @organization.id, active: true })
                    .active
                    .find(id)
    end

    def record_activity(order)
      return unless order.listing

      ActivityEvent.create!(organization: @organization, actor: nil, subject: order, event_type: "order.created",
                            payload: {
                              listing_id: order.listing_id,
                              order_id: order.id,
                              order_item_ids: order.order_items.ids,
                              total_cents: order.total_cents,
                              payment_mode: order.payment_mode
                            })
      ActivityEvent.create!(organization: @organization, actor: nil, subject: order.listing, event_type: "order.created",
                            payload: {
                              order_id: order.id,
                              order_item_ids: order.order_items.ids,
                              total_cents: order.total_cents,
                              payment_mode: order.payment_mode
                            })
    end
  end
end

module ClientPortal
  # A customer books a shoot: the listing, and when they chose services, the
  # order for them under the same team. Either both exist or neither does, and
  # only services on the team's order form can be booked.
  class BookShoot < ApplicationInteractor
    def call
      account = context.fetch(:client_account)
      actor = context.fetch(:actor)
      items = Array(context[:items]).map { |item| item.to_h.symbolize_keys }.reject { |item| item[:product_variant_id].blank? }
      refuse_unbookable!(account, items)

      ActiveRecord::Base.transaction do
        listing_result = CreateListing.call(organization: context.fetch(:organization), client_account: account, actor:,
                                            attributes: context.fetch(:attributes))
        raise listing_result.failure if listing_result.failure?

        listing = listing_result.fetch(:listing)
        context.set(:listing, listing)
        next if items.empty?

        order_result = Orders::Create.call(
          organization: context.fetch(:organization), ordered_by: actor,
          attributes: { client_account_id: account.id, listing_id: listing.id, payment_mode: "pay_later", items: }
        )
        raise order_result.failure if order_result.failure?

        order = order_result.fetch(:order)
        order.update!(source: "portal") if order.source != "portal"
        context.set(:order, order)
      end

      context
    end

    private

    def refuse_unbookable!(account, items)
      variant_ids = items.map { |item| item[:product_variant_id].to_i }
      bookable = ProductVariant.active.where(id: variant_ids, product_id: account.bookable_products.select(:id)).count
      return if bookable == variant_ids.uniq.size

      context.fail!(code: "portal_booking_service_unavailable", message: "One of those services cannot be booked for this team")
    end
  end
end

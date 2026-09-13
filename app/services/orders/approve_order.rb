module Orders
  class ApproveOrder < ApplicationInteractor
    def call
      order = context.fetch(:order)
      actor = context[:actor]
      already_materialized = false

      Order.transaction do
        order.lock!
        already_materialized = order.approved? && order.approved_at.present? && order.order_deliverables.exists?
        order.update!(status: :approved, approved_at: (order.approved_at || Time.current))
        Orders::DeliverableMaterializer.new(order:).call
        record_activity(order, actor) unless already_materialized
      end

      context.set(:order, order)
    end

    private

    def record_activity(order, actor)
      ActivityEvent.create!(organization: order.organization, actor:, subject: order,
                            event_type: "order.approved", payload: {
                              order_id: order.id,
                              order_deliverable_ids: order.order_deliverables.ids
                            })
      return unless order.listing

      ActivityEvent.create!(organization: order.organization, actor:, subject: order.listing,
                            event_type: "order.approved", payload: { order_id: order.id })
    end
  end
end

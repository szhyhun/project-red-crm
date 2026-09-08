module Orders
  class Approval
    def initialize(order:, actor: nil)
      @order = order
      @actor = actor
    end

    def call
      already_materialized = false
      Order.transaction do
        @order.lock!
        already_materialized = @order.approved? && @order.approved_at.present? && @order.order_deliverables.exists?
        @order.update!(status: :approved, approved_at: (@order.approved_at || Time.current))
        Orders::DeliverableMaterializer.new(order: @order).call
        record_activity unless already_materialized
      end

      # A previous approval may have committed the deliverables before the
      # queue was unavailable. Triggering again is safe because Trigger uses a
      # workflow-version idempotency key and only schedules unfinished runs.
      Workflows::Trigger.new(order: @order.reload).enqueue!
      @order
    end

    alias approve! call

    private

    def record_activity
      ActivityEvent.create!(organization: @order.organization, actor: @actor, subject: @order,
                            event_type: "order.approved", payload: {
                              order_id: @order.id,
                              order_deliverable_ids: @order.order_deliverables.ids
                            })
      return unless @order.listing

      ActivityEvent.create!(organization: @order.organization, actor: @actor, subject: @order.listing,
                            event_type: "order.approved", payload: { order_id: @order.id })
    end
  end

  Approver = Approval
end

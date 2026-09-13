module Orders
  class EnqueueWorkflow < ApplicationInteractor
    def call
      order = context.fetch(:order).reload
      Workflows::Trigger.new(order:).enqueue!
      context.set(:order, order)
    end
  end
end

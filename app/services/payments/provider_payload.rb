module Payments
  module ProviderPayload
    SAFE_STRIPE_FIELDS = %w[id status amount amount_received currency livemode].freeze

    module_function

    def stripe(payment_intent)
      payload = payment_intent.to_hash.to_h.transform_keys(&:to_s)
      payload.slice(*SAFE_STRIPE_FIELDS)
    end
  end
end

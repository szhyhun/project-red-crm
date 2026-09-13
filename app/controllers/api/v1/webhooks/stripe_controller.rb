class Api::V1::Webhooks::StripeController < ApplicationController
  skip_before_action :verify_authenticity_token

  def create
    event = Stripe::Webhook.construct_event(
      request.raw_post,
      request.headers["Stripe-Signature"],
      ENV.fetch("STRIPE_WEBHOOK_SECRET")
    )
    result = Payments::ProcessStripeWebhook.call(event:)
    raise result.failure.original_error || result.failure if result.failure?
    head :ok
  rescue JSON::ParserError, Stripe::SignatureVerificationError
    head :bad_request
  end
end

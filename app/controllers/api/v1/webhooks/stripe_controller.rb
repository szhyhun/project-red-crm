class Api::V1::Webhooks::StripeController < ApplicationController
  skip_before_action :verify_authenticity_token

  def create
    event = Stripe::Webhook.construct_event(
      request.raw_post,
      request.headers["Stripe-Signature"],
      ENV.fetch("STRIPE_WEBHOOK_SECRET")
    )
    Payments::StripeWebhookProcessor.new(event:).process!
    head :ok
  rescue JSON::ParserError, Stripe::SignatureVerificationError
    head :bad_request
  end
end

class PaymentWebhookEvent < ApplicationRecord
  belongs_to :payment, optional: true

  validates :provider, :event_id, :event_type, presence: true
end

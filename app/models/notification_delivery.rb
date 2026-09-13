class NotificationDelivery < ApplicationRecord
  belongs_to :organization
  belongs_to :notifiable, polymorphic: true

  enum :channel, { email: "email", sms: "sms", push: "push" }, prefix: :by, validate: true
  enum :status, { pending: "pending", processing: "processing", delivered: "delivered", failed: "failed" }, validate: true

  validates :kind, :recipient, :deduplication_key, presence: true
end

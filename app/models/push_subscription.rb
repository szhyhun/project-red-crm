class PushSubscription < ApplicationRecord
  belongs_to :user

  validates :endpoint, :p256dh, :auth, presence: true
  validates :endpoint, uniqueness: true, format: { with: %r{\Ahttps://}, message: "must be an https URL" }
end

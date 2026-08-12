class AppointmentEvent < ApplicationRecord
  belongs_to :appointment
  belongs_to :actor, class_name: "User", optional: true

  validates :event_type, presence: true
end

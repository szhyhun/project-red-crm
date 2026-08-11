class ActivityEvent < ApplicationRecord
  belongs_to :organization
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :subject, polymorphic: true

  validates :event_type, presence: true
end

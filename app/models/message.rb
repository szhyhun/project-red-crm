class Message < ApplicationRecord
  belongs_to :conversation
  belongs_to :author, class_name: "User"

  enum :visibility, { participants: "participants", staff_only: "staff_only" }, validate: true

  validates :body, presence: true
end

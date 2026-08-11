class ListingAssignment < ApplicationRecord
  belongs_to :listing
  belongs_to :user

  validates :role, inclusion: { in: %w[manager photographer videographer editor] }
end

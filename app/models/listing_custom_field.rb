class ListingCustomField < ApplicationRecord
  belongs_to :listing

  validates :name, presence: true
  validates :name, uniqueness: { scope: :listing_id }
end

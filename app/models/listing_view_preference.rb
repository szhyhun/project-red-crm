class ListingViewPreference < ApplicationRecord
  belongs_to :user

  enum :display_mode, { grid: "grid", list: "list" }, validate: true
end

class RecordWhoPlacedOrdersAndBookings < ActiveRecord::Migration[8.0]
  def change
    # A team's work and one person's share of it are told apart by who placed
    # it: the order names the person who ordered, the listing who booked it.
    add_reference :orders, :ordered_by, foreign_key: { to_table: :users, on_delete: :nullify }
    add_reference :listings, :booked_by, foreign_key: { to_table: :users, on_delete: :nullify }
  end
end

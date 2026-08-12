class AddCustomerDeliveryTracking < ActiveRecord::Migration[8.0]
  def change
    add_column :listings, :customer_first_viewed_at, :datetime
    add_index :listings, :customer_first_viewed_at
  end
end

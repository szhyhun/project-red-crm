class ExpandOrderItems < ActiveRecord::Migration[8.0]
  def change
    add_column :order_items, :description, :text
    add_column :order_items, :options, :jsonb, null: false, default: {}
    add_column :order_items, :cancelled_at, :datetime
    add_index :order_items, :cancelled_at
  end
end

class AddMediaOrderSources < ActiveRecord::Migration[8.0]
  def change
    add_reference :media_assets, :order, foreign_key: true
    add_reference :media_assets, :order_item, foreign_key: true
    add_index :media_assets, %i[order_id order_item_id]
  end
end

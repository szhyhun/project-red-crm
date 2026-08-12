class ExpandMediaManagement < ActiveRecord::Migration[8.0]
  def change
    add_column :media_assets, :position, :integer, null: false, default: 0
    add_column :media_assets, :cover, :boolean, null: false, default: false
    add_column :media_assets, :hidden, :boolean, null: false, default: false
    add_index :media_assets, %i[listing_id category position]
    add_index :media_assets, %i[listing_id cover]
  end
end

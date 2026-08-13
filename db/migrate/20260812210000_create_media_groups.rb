class CreateMediaGroups < ActiveRecord::Migration[8.0]
  def change
    create_table :media_groups do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :listing, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      # Groups are an internal organising tool by default; publishing them to the
      # property site is opt-in per group.
      t.boolean :customer_visible, null: false, default: true
      t.timestamps
    end

    add_index :media_groups, %i[listing_id position]
    add_index :media_groups, %i[listing_id name], unique: true

    # Ungrouped assets keep a null group, which is the "Images" bucket in the UI.
    add_reference :media_assets, :media_group, foreign_key: true, null: true
    add_index :media_assets, %i[media_group_id position]
  end
end

class AddRichNotesAndExternalMedia < ActiveRecord::Migration[8.0]
  def change
    add_column :listing_notes, :body_format, :string, null: false, default: "plain"

    change_column_null :media_assets, :storage_key, true
    add_column :media_assets, :source_url, :text
    add_index :media_assets, :source_url
  end
end

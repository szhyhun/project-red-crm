class CreateTags < ActiveRecord::Migration[8.0]
  def change
    # Coloured labels staff put on customer teams, to group and filter them.
    create_table :tags do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.string :color, null: false, default: "#6b7280"
      t.timestamps
    end
    add_index :tags, "organization_id, LOWER(name)", unique: true, name: "index_tags_on_organization_and_lower_name"
    add_check_constraint :tags, "color ~ '^#[0-9a-fA-F]{6}$'", name: "tags_color_is_hex"

    create_table :client_account_tags do |t|
      t.references :client_account, null: false, foreign_key: { on_delete: :cascade }
      t.references :tag, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end
    add_index :client_account_tags, [ :client_account_id, :tag_id ], unique: true
  end
end

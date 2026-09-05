class CreateBoardsAndUserGroups < ActiveRecord::Migration[8.0]
  def change
    create_table :boards do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :kind, null: false, default: "production"
      t.string :visibility, null: false, default: "organization"
      t.boolean :requires_listing, null: false, default: true
      t.boolean :client_visible, null: false, default: true
      t.boolean :archived, null: false, default: false
      t.integer :position, null: false, default: 0
      t.references :created_by, foreign_key: { to_table: :users }
      t.jsonb :settings, null: false, default: {}
      t.timestamps
    end
    add_index :boards, [ :organization_id, :slug ], unique: true
    add_index :boards, [ :organization_id, :archived, :position ]

    create_table :user_groups do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.timestamps
    end
    add_index :user_groups, [ :organization_id, :slug ], unique: true

    create_table :user_group_memberships do |t|
      t.references :user_group, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :user_group_memberships, [ :user_group_id, :user_id ], unique: true

    # The grantee is a person or a group, so the association is polymorphic
    # rather than two nullable columns that would need a check constraint to
    # keep exactly one of them populated.
    create_table :board_memberships do |t|
      t.references :board, null: false, foreign_key: true
      t.string :member_type, null: false
      t.bigint :member_id, null: false
      t.string :access, null: false, default: "contributor"
      t.timestamps
    end
    add_index :board_memberships, [ :board_id, :member_type, :member_id ], unique: true,
              name: "index_board_memberships_on_board_and_member"
    add_index :board_memberships, [ :member_type, :member_id ]
  end
end

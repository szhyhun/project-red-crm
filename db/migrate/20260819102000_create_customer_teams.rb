class CreateCustomerTeams < ActiveRecord::Migration[8.0]
  def change
    create_table :customer_teams do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.string :brokerage_name
      t.string :brokerage_website
      t.string :website
      t.string :logo_url
      t.text :description
      t.boolean :archived, null: false, default: false
      t.timestamps
    end
    add_index :customer_teams, "organization_id, lower(name)", unique: true, name: "index_customer_teams_on_organization_and_lower_name"
    add_index :customer_teams, [ :organization_id, :archived ]

    create_table :customer_team_memberships do |t|
      t.references :customer_team, null: false, foreign_key: true
      t.references :client_account, null: false, foreign_key: true
      t.boolean :primary, null: false, default: false
      t.timestamps
    end
    add_index :customer_team_memberships, [ :customer_team_id, :client_account_id ], unique: true
  end
end

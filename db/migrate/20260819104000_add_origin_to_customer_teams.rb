class AddOriginToCustomerTeams < ActiveRecord::Migration[8.0]
  def change
    add_column :customer_teams, :origin, :string, null: false, default: "native"
    add_index :customer_teams, [ :organization_id, :origin ]
  end
end

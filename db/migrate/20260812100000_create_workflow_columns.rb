class CreateWorkflowColumns < ActiveRecord::Migration[8.0]
  def change
    create_table :workflow_columns do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :key, null: false
      t.string :name, null: false
      t.string :color, null: false, default: "#171525"
      t.string :category, null: false, default: "active"
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :workflow_columns, %i[organization_id key], unique: true
    add_index :workflow_columns, %i[organization_id position]

    reversible do |direction|
      direction.up do
        execute <<~SQL.squish
          INSERT INTO workflow_columns (organization_id, key, name, color, category, position, created_at, updated_at)
          SELECT organizations.id, defaults.key, defaults.name, defaults.color, defaults.category, defaults.position, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
          FROM organizations
          CROSS JOIN (VALUES
            ('todo', 'Todo', '#f7f6f8', 'active', 0),
            ('in_progress', 'In Progress', '#aec7f7', 'active', 1),
            ('blocked', 'Blocked', '#e6190b', 'blocked', 2),
            ('done', 'Done', '#3cb371', 'completed', 3)
          ) AS defaults(key, name, color, category, position)
        SQL
      end
    end
  end
end

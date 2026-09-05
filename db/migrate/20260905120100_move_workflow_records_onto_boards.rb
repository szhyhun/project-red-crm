class MoveWorkflowRecordsOntoBoards < ActiveRecord::Migration[8.0]
  def up
    add_reference :workflow_columns, :board, foreign_key: true
    add_reference :workflow_tasks, :board, foreign_key: true

    add_reference :workflow_tasks, :reporter, foreign_key: { to_table: :users }
    add_column :workflow_tasks, :labels, :string, array: true, null: false, default: []
    add_column :workflow_tasks, :started_at, :datetime
    add_column :workflow_tasks, :external_ref, :string

    backfill_default_boards!

    change_column_null :workflow_columns, :board_id, false
    change_column_null :workflow_tasks, :board_id, false

    # A task on an internal board describes work that is not about a property,
    # so the listing becomes optional here and stays required per board through
    # Board#requires_listing.
    change_column_null :workflow_tasks, :listing_id, true

    # Column keys only have to be unique inside their own board. Two boards both
    # wanting a "Done" column is the normal case, not a conflict.
    remove_index :workflow_columns, column: [ :organization_id, :key ]
    add_index :workflow_columns, [ :board_id, :key ], unique: true
    add_index :workflow_columns, [ :board_id, :position ]

    add_index :workflow_tasks, [ :board_id, :status, :position ]
    add_index :workflow_tasks, :labels, using: :gin
  end

  def down
    remove_index :workflow_tasks, :labels
    remove_index :workflow_tasks, column: [ :board_id, :status, :position ]
    remove_index :workflow_columns, column: [ :board_id, :position ]
    remove_index :workflow_columns, column: [ :board_id, :key ]
    add_index :workflow_columns, [ :organization_id, :key ], unique: true

    execute "DELETE FROM workflow_tasks WHERE listing_id IS NULL"
    change_column_null :workflow_tasks, :listing_id, false

    remove_column :workflow_tasks, :external_ref
    remove_column :workflow_tasks, :started_at
    remove_column :workflow_tasks, :labels
    remove_reference :workflow_tasks, :reporter
    remove_reference :workflow_tasks, :board
    remove_reference :workflow_columns, :board
  end

  private

  # Every organization already has exactly one implicit board: its set of
  # workflow columns. That becomes a real Production board so nothing changes
  # for anyone already using it.
  def backfill_default_boards!
    now = Time.current

    select_values("SELECT id FROM organizations ORDER BY id").each do |organization_id|
      board_id = insert_production_board(organization_id, now)

      execute <<~SQL.squish
        UPDATE workflow_columns SET board_id = #{board_id}, updated_at = #{quote(now)}
        WHERE organization_id = #{organization_id} AND board_id IS NULL
      SQL
      execute <<~SQL.squish
        UPDATE workflow_tasks SET board_id = #{board_id}, updated_at = #{quote(now)}
        WHERE organization_id = #{organization_id} AND board_id IS NULL
      SQL
    end
  end

  def insert_production_board(organization_id, now)
    select_value(<<~SQL.squish)
      INSERT INTO boards (organization_id, name, slug, kind, visibility, requires_listing,
                          client_visible, archived, position, settings, created_at, updated_at)
      VALUES (#{organization_id}, 'Production', 'production', 'production', 'organization',
              TRUE, TRUE, FALSE, 0, '{}', #{quote(now)}, #{quote(now)})
      RETURNING id
    SQL
  end
end

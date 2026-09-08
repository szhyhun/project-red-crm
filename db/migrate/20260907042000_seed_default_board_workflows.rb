class SeedDefaultBoardWorkflows < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      INSERT INTO board_workflows
        (organization_id, board_id, name, enabled, trigger_key, is_default, workflow_version, created_at, updated_at)
      SELECT boards.organization_id, boards.id, 'Create production work', TRUE, 'order_approved', TRUE, 1, NOW(), NOW()
      FROM boards
      WHERE boards.kind = 'production'
        AND boards.archived = FALSE
        AND NOT EXISTS (
          SELECT 1 FROM board_workflows workflows
          WHERE workflows.board_id = boards.id AND workflows.is_default = TRUE
        )
    SQL

    execute <<~SQL
      INSERT INTO board_workflow_actions
        (board_workflow_id, action_type, configuration, position, created_at, updated_at)
      SELECT workflows.id, 'create_parent_task', '{"title":"Production"}'::jsonb, 0, NOW(), NOW()
      FROM board_workflows workflows
      WHERE workflows.is_default = TRUE
        AND NOT EXISTS (
          SELECT 1 FROM board_workflow_actions actions
          WHERE actions.board_workflow_id = workflows.id
        )
    SQL

    execute <<~SQL
      INSERT INTO board_workflow_actions
        (board_workflow_id, action_type, configuration, position, created_at, updated_at)
      SELECT workflows.id, 'create_or_group_child_task', '{"customer_visible":true}'::jsonb, 1, NOW(), NOW()
      FROM board_workflows workflows
      WHERE workflows.is_default = TRUE
        AND EXISTS (
          SELECT 1 FROM board_workflow_actions actions
          WHERE actions.board_workflow_id = workflows.id AND actions.action_type = 'create_parent_task'
        )
        AND NOT EXISTS (
          SELECT 1 FROM board_workflow_actions actions
          WHERE actions.board_workflow_id = workflows.id AND actions.action_type = 'create_or_group_child_task'
        )
    SQL

    execute <<~SQL
      INSERT INTO board_workflow_actions
        (board_workflow_id, action_type, configuration, position, created_at, updated_at)
      SELECT workflows.id, 'place_on_board', jsonb_build_object('board_id', workflows.board_id, 'column_key', 'todo'), 2, NOW(), NOW()
      FROM board_workflows workflows
      WHERE workflows.is_default = TRUE
        AND NOT EXISTS (
          SELECT 1 FROM board_workflow_actions actions
          WHERE actions.board_workflow_id = workflows.id AND actions.action_type = 'place_on_board'
        )
    SQL

    execute <<~SQL
      INSERT INTO board_workflow_status_mappings
        (board_workflow_id, source_status, target_column_key, position, created_at, updated_at)
      SELECT workflows.id,
             requested.source_status,
             COALESCE(
               CASE requested.source_status
                 WHEN 'not_started' THEN (
                   SELECT columns.key
                   FROM workflow_columns columns
                   WHERE columns.board_id = workflows.board_id AND columns.key = 'todo'
                   LIMIT 1
                 )
                 WHEN 'in_progress' THEN (
                   SELECT columns.key
                   FROM workflow_columns columns
                   WHERE columns.board_id = workflows.board_id AND columns.key = 'in_progress'
                   LIMIT 1
                 )
                 WHEN 'in_review' THEN (
                   SELECT columns.key
                   FROM workflow_columns columns
                   WHERE columns.board_id = workflows.board_id
                     AND (columns.key ILIKE '%review%' OR columns.key ILIKE '%qa%' OR columns.key ILIKE '%approval%')
                   ORDER BY columns.position, columns.id
                   LIMIT 1
                 )
                 WHEN 'delivered' THEN (
                   SELECT columns.key
                   FROM workflow_columns columns
                   WHERE columns.board_id = workflows.board_id AND columns.category = 'completed'
                   ORDER BY columns.position, columns.id
                   LIMIT 1
                 )
               END,
               CASE requested.source_status
                 WHEN 'in_review' THEN (
                   SELECT columns.key
                   FROM workflow_columns columns
                   WHERE columns.board_id = workflows.board_id AND columns.key = 'in_progress'
                   LIMIT 1
                 )
               END,
               (
                 SELECT columns.key
                 FROM workflow_columns columns
                 WHERE columns.board_id = workflows.board_id
                   AND (requested.source_status <> 'delivered' OR columns.category = 'completed')
                 ORDER BY columns.position, columns.id
                 LIMIT 1
               ),
               (
                 SELECT columns.key
                 FROM workflow_columns columns
                 WHERE columns.board_id = workflows.board_id
                 ORDER BY columns.position, columns.id
                 LIMIT 1
               )
             ),
             requested.position,
             NOW(),
             NOW()
      FROM board_workflows workflows
      CROSS JOIN (VALUES
        ('not_started', 0),
        ('in_progress', 1),
        ('in_review', 2),
        ('delivered', 3)
      ) AS requested(source_status, position)
      WHERE workflows.is_default = TRUE
        AND NOT EXISTS (
          SELECT 1
          FROM board_workflow_status_mappings mappings
          WHERE mappings.board_workflow_id = workflows.id
            AND mappings.source_status = requested.source_status
        )
      ON CONFLICT (board_workflow_id, source_status) DO NOTHING
    SQL
  end

  def down
    execute "DELETE FROM board_workflow_status_mappings WHERE board_workflow_id IN (SELECT id FROM board_workflows WHERE is_default = TRUE)"
    execute "DELETE FROM board_workflow_actions WHERE board_workflow_id IN (SELECT id FROM board_workflows WHERE is_default = TRUE)"
    execute "DELETE FROM board_workflows WHERE is_default = TRUE"
  end
end

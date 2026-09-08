class BackfillMediaWorkflowRelationships < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      INSERT INTO workflow_task_placements
        (workflow_task_id, board_id, workflow_column_id, position, is_home, created_at, updated_at)
      SELECT tasks.id, tasks.board_id, columns.id, tasks.position, TRUE, NOW(), NOW()
      FROM workflow_tasks tasks
      INNER JOIN workflow_columns columns
        ON columns.board_id = tasks.board_id AND columns.key = tasks.status
      WHERE NOT EXISTS (
        SELECT 1 FROM workflow_task_placements placements
        WHERE placements.workflow_task_id = tasks.id
      )
    SQL

    # Keep the old listing on each message as context, then make the
    # conversation itself account-wide. Attachments and read timestamps are
    # moved before the duplicate conversation is removed.
    execute <<~SQL
      UPDATE messages
      SET listing_id = conversations.listing_id
      FROM conversations
      WHERE messages.conversation_id = conversations.id
        AND messages.listing_id IS NULL
        AND conversations.kind = 'client'
    SQL

    execute <<~SQL
      DO $$
      DECLARE
        duplicate_group RECORD;
        duplicate_id BIGINT;
        keeper_id BIGINT;
      BEGIN
        FOR duplicate_group IN
          SELECT organization_id, client_account_id, MIN(id) AS keeper_id
          FROM conversations
          WHERE kind = 'client' AND client_account_id IS NOT NULL
          GROUP BY organization_id, client_account_id
          HAVING COUNT(*) > 1
        LOOP
          keeper_id := duplicate_group.keeper_id;
          FOR duplicate_id IN
            SELECT id FROM conversations
            WHERE organization_id = duplicate_group.organization_id
              AND client_account_id = duplicate_group.client_account_id
              AND kind = 'client'
              AND id <> keeper_id
          LOOP
            INSERT INTO conversation_memberships
              (conversation_id, user_id, role, last_read_at, created_at, updated_at)
            SELECT keeper_id, user_id, role, last_read_at, NOW(), NOW()
            FROM conversation_memberships
            WHERE conversation_id = duplicate_id
            ON CONFLICT (conversation_id, user_id) DO UPDATE
              SET last_read_at = CASE
                WHEN conversation_memberships.last_read_at IS NULL THEN EXCLUDED.last_read_at
                WHEN EXCLUDED.last_read_at IS NULL THEN conversation_memberships.last_read_at
                ELSE GREATEST(conversation_memberships.last_read_at, EXCLUDED.last_read_at)
              END,
              updated_at = NOW();

            UPDATE messages SET conversation_id = keeper_id WHERE conversation_id = duplicate_id;
            UPDATE conversation_attachments SET conversation_id = keeper_id WHERE conversation_id = duplicate_id;
            DELETE FROM conversation_memberships WHERE conversation_id = duplicate_id;
            DELETE FROM conversations WHERE id = duplicate_id;
          END LOOP;

          UPDATE conversations
          SET listing_id = NULL,
              last_message_at = GREATEST(last_message_at, (SELECT MAX(created_at) FROM messages WHERE conversation_id = keeper_id)),
              updated_at = NOW()
          WHERE id = keeper_id;
        END LOOP;
      END $$;
    SQL

    execute <<~SQL
      UPDATE conversations
      SET listing_id = NULL, updated_at = NOW()
      WHERE kind = 'client' AND client_account_id IS NOT NULL
    SQL

    add_index :conversations, %i[organization_id client_account_id], unique: true,
              where: "kind = 'client' AND client_account_id IS NOT NULL",
              name: "index_one_client_conversation_per_account"
  end

  def down
    remove_index :conversations, name: "index_one_client_conversation_per_account"
    execute "DELETE FROM workflow_task_placements"
  end
end

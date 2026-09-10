class AddPositionToConversationMemberships < ActiveRecord::Migration[8.0]
  def up
    add_column :conversation_memberships, :position, :integer, null: false, default: 0

    execute <<~SQL
      WITH ranked_memberships AS (
        SELECT conversation_memberships.id,
               ROW_NUMBER() OVER (
                 PARTITION BY conversation_memberships.user_id
                 ORDER BY conversations.created_at, conversations.id
               ) - 1 AS position
        FROM conversation_memberships
        INNER JOIN conversations ON conversations.id = conversation_memberships.conversation_id
        WHERE conversations.kind = 'internal'
      )
      UPDATE conversation_memberships
      SET position = ranked_memberships.position
      FROM ranked_memberships
      WHERE conversation_memberships.id = ranked_memberships.id
    SQL
  end

  def down
    remove_column :conversation_memberships, :position
  end
end

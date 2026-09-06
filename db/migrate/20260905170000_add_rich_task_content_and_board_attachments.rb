class AddRichTaskContentAndBoardAttachments < ActiveRecord::Migration[8.0]
  def change
    add_column :workflow_tasks, :description_html, :text
    add_column :task_comments, :body_html, :text

    create_table :board_attachments do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :board, null: false, foreign_key: true
      t.references :workflow_task, null: false, foreign_key: true
      t.references :task_comment, foreign_key: true
      t.references :uploaded_by, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "pending"
      t.string :storage_key, null: false
      t.string :filename, null: false
      t.string :content_type, null: false
      t.bigint :byte_size, null: false, default: 0
      t.integer :width
      t.integer :height
      t.integer :duration_seconds
      t.jsonb :metadata, null: false, default: {}
      t.datetime :processed_at
      t.timestamps
    end

    add_index :board_attachments, :storage_key, unique: true
    add_index :board_attachments, [ :workflow_task_id, :created_at ]
    add_index :board_attachments, [ :task_comment_id, :created_at ]
    add_index :board_attachments, [ :board_id, :status ]
  end
end

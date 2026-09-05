class CreateTaskCommentsAndChecklistItems < ActiveRecord::Migration[8.0]
  def change
    create_table :task_comments do |t|
      t.references :workflow_task, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.text :body, null: false
      t.datetime :edited_at
      t.timestamps
    end
    add_index :task_comments, [ :workflow_task_id, :created_at ]

    create_table :task_checklist_items do |t|
      t.references :workflow_task, null: false, foreign_key: true
      t.references :completed_by, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.integer :position, null: false, default: 0
      t.datetime :completed_at
      t.timestamps
    end
    add_index :task_checklist_items, [ :workflow_task_id, :position ]
  end
end

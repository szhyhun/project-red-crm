class AddParentCommentsAndTaskActivity < ActiveRecord::Migration[8.0]
  def change
    add_reference :task_comments, :parent_comment, foreign_key: { to_table: :task_comments }
    add_index :task_comments, [ :parent_comment_id, :created_at ]
  end
end

class RemoveStageFromWorkflowTasks < ActiveRecord::Migration[8.0]
  def up
    index_name = "index_workflow_tasks_on_organization_id_and_status_and_stage"
    remove_index :workflow_tasks, name: index_name if index_exists?(:workflow_tasks, name: index_name)
    remove_column :workflow_tasks, :stage
  end

  def down
    add_column :workflow_tasks, :stage, :string, null: false, default: "work"
    add_index :workflow_tasks, %i[organization_id status stage], name: "index_workflow_tasks_on_organization_id_and_status_and_stage"
  end
end

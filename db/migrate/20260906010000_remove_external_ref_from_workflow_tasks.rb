class RemoveExternalRefFromWorkflowTasks < ActiveRecord::Migration[8.0]
  def up
    # Plan references were documentation metadata, not part of a workflow task.
    remove_column :workflow_tasks, :external_ref, :string
  end

  def down
    add_column :workflow_tasks, :external_ref, :string
  end
end

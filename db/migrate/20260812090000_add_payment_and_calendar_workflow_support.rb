class AddPaymentAndCalendarWorkflowSupport < ActiveRecord::Migration[8.0]
  def change
    add_column :appointments, :calendar_color, :string
    add_column :workflow_tasks, :description, :text
    add_column :workflow_tasks, :priority, :string, null: false, default: "normal"
    add_index :workflow_tasks, %i[organization_id status position]

    add_index :payments, %i[invoice_id status]
  end
end

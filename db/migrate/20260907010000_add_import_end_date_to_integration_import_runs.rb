class AddImportEndDateToIntegrationImportRuns < ActiveRecord::Migration[8.0]
  def change
    add_column :integration_import_runs, :import_end_date, :date
  end
end

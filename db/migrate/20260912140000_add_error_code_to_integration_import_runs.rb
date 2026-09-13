class AddErrorCodeToIntegrationImportRuns < ActiveRecord::Migration[8.0]
  def change
    add_column :integration_import_runs, :error_code, :string
    add_index :integration_import_runs, :error_code
  end
end

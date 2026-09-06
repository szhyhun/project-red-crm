class RenameListingStartDateToImportStartDate < ActiveRecord::Migration[8.0]
  def up
    rename_column :integration_import_runs, :listing_start_date, :import_start_date
  end

  def down
    rename_column :integration_import_runs, :import_start_date, :listing_start_date
  end
end

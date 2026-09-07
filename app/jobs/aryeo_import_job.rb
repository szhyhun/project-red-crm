class AryeoImportJob < ApplicationJob
  queue_as :integrations

  def perform(import_run_id)
    run = IntegrationImportRun.find(import_run_id)
    Aryeo::Importer.new(
      run:,
      resources: run.requested_resources,
      import_start_date: run.import_start_date,
      import_end_date: run.import_end_date,
      conflict_resolution: run.conflict_resolution
    ).call
  end
end

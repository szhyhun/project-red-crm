class AryeoImportJob < ApplicationJob
  queue_as :integrations

  def perform(import_run_id)
    run = IntegrationImportRun.find(import_run_id)
    Aryeo::Importer.new(
      run:,
      resources: run.requested_resources,
      listing_start_date: run.listing_start_date,
      conflict_resolution: run.conflict_resolution
    ).call
  end
end

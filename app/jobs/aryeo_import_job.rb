class AryeoImportJob < ApplicationJob
  queue_as :integrations

  def perform(import_run_id)
    failure_recorded = false
    run = IntegrationImportRun.find(import_run_id)
    context = ApplicationInteractor::Context.new(run:)
    result = Integrations::Aryeo::Organizers::ImportOrganizer.call(context:)
    return if result.success?

    failure = result.failure
    error = failure.original_error || failure
    fail_import(run, context, error)
    failure_recorded = true
    Rails.logger.error("Aryeo import #{import_run_id} failed: #{failure.class}: #{failure.message}")
    raise error
  rescue StandardError => error
    fail_import(run, context, error) if !failure_recorded && defined?(run) && run.present?
    Rails.logger.error("Aryeo import #{import_run_id} failed: #{error.class}: #{error.message}")
    raise
  end

  private

  def fail_import(run, context, error)
    Integrations::Aryeo::Actions::FailImport.call(run:, session: context[:session], error:)
  end
end

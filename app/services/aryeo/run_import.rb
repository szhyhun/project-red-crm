module Aryeo
  class RunImport < ApplicationInteractor
    def call
      run = context.fetch(:run)
      Importer.new(
        run:,
        resources: run.requested_resources,
        import_start_date: run.import_start_date,
        import_end_date: run.import_end_date,
        conflict_resolution: run.conflict_resolution
      ).call
      context.set(:run, run.reload)
    rescue StandardError => error
      run&.mark_failed!("#{error.class}: #{error.message}")
      context.fail!(code: "aryeo_import_failed", message: error.message, original_error: error, run_id: run&.id)
    end
  end
end

module Integrations::Aryeo::Actions
  class FailImport < ApplicationInteractor
    def call
      run = context.fetch(:run)
      error = context.fetch(:error)
      importer = context[:importer]
      state = importer&.state || empty_state

      run.mark_failed!("#{error.class}: #{error.message}", counts: state[:counts], coverage: state[:coverage],
                       error_details: state[:errors], error_code: error_code_for(error))
      run.integration_connection.update!(status: :invalid) if error.is_a?(::Aryeo::Client::Error)

      context.set(:run, run.reload).set(:error, error).set(:error_code, error_code_for(error))
    end

    private

    def error_code_for(error)
      return "endpoint_failure" if error.is_a?(::Aryeo::Client::Error)
      return "record_validation_failure" if error.is_a?(ActiveRecord::RecordInvalid)

      "import_failure"
    end

    def empty_state
      {
        counts: {},
        coverage: {},
        errors: [],
        deferred_skipped_resources: [],
        dependency_counts: {},
        dependency_conflict_counts: {}
      }
    end
  end
end

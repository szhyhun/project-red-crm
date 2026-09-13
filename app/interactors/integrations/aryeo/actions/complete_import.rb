module Integrations::Aryeo::Actions
  class CompleteImport < ApplicationInteractor
    def call
      return context if context[:skipped]

      run = context.fetch(:run)
      importer = context.fetch(:importer)
      state = importer.state

      state.fetch(:deferred_skipped_resources).each do |name|
        state[:coverage][name] ||= { status: "skipped", detail: "Not selected for this import run" }
      end
      state[:dependency_counts].keys.union(state[:dependency_conflict_counts].keys).each do |name|
        count = state[:dependency_counts][name]
        skipped_conflicts = state[:dependency_conflict_counts][name]
        next if count.zero? && skipped_conflicts.zero?

        state[:coverage][name] = {
          status: "imported_as_dependency",
          count: count,
          skipped_conflicts: skipped_conflicts
        }.compact
      end

      status = state[:errors].empty? ? :completed : :completed_with_errors
      Rails.logger.warn("Aryeo import #{run.id} completed with errors: #{state[:errors].join('; ')}") if state[:errors].present?
      run.update!(status:, phase: "completed", completed_at: Time.current, heartbeat_at: Time.current,
                  counts: state[:counts], coverage: state[:coverage], error_details: state[:errors])
      run.integration_connection.update!(status: :connected, last_imported_at: Time.current,
                                         endpoint_coverage: state[:coverage])

      context.set(:run, run.reload).set(:status, status)
    end
  end
end

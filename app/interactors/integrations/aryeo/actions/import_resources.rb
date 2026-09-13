module Integrations::Aryeo::Actions
  class ImportResources < ApplicationInteractor
    def call
      return context if context[:skipped]

      run = context.fetch(:run)
      importer = context[:importer] || build_importer(run)
      importer.import_collections!
      context.set(:importer, importer)
    end

    private

    def build_importer(run)
      options = {
        run:,
        resources: context[:resources] || run.requested_resources,
        import_start_date: context[:import_start_date] || run.import_start_date,
        import_end_date: context[:import_end_date] || run.import_end_date,
        conflict_resolution: context[:conflict_resolution] || run.conflict_resolution
      }
      options[:client] = context[:client] if context[:client]
      options[:listing_limit] = context[:listing_limit] if context[:listing_limit]
      options[:skip_resources] = context[:skip_resources] if context[:skip_resources].present?
      ::Aryeo::Importer.new(**options)
    end
  end
end

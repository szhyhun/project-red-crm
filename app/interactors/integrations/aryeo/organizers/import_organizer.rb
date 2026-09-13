module Integrations
  module Aryeo
    module Organizers
      class ImportOrganizer < ApplicationOrganizer
        organize Integrations::Aryeo::Actions::StartImport,
                 Integrations::Aryeo::Actions::ImportSelectedCollections,
                 Integrations::Aryeo::Actions::ReconcileImportedDelivery,
                 Integrations::Aryeo::Actions::CompleteImport

        def call
          result = super
          return result unless result.failure?

          fail_import(result.failure)
          result
        rescue StandardError => error
          fail_import(error)
          context.fail!(code: "aryeo_import_failed", message: error.message, original_error: error,
                        run_id: context[:run]&.id)
        end

        private

        def fail_import(error)
          Integrations::Aryeo::Actions::FailImport.call(
            run: context.fetch(:run),
            session: context[:session],
            error: error.respond_to?(:original_error) ? (error.original_error || error) : error
          )
        end
      end
    end
  end
end

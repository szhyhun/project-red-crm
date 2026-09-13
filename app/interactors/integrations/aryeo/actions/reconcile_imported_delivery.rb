module Integrations::Aryeo::Actions
  class ReconcileImportedDelivery < ApplicationInteractor
    def call
      return context if context[:skipped]

      context.fetch(:importer).reconcile_imported_delivery!
      context
    end
  end
end

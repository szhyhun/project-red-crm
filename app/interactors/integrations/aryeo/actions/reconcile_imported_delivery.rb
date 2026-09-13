module Integrations::Aryeo::Actions
  class ReconcileImportedDelivery < ApplicationInteractor
    def call
      return context if context[:skipped]

      session = context.fetch(:session)
      result = ::Aryeo::ImportedDeliveryMaterializer.new(run: context.fetch(:run)).call
      session.record_linked_media!(result.fetch(:linked_media_assets).size)
      context.set(:materialization, result)
    end
  end
end

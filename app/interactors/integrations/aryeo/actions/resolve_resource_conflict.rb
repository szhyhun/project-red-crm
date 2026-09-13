module Integrations::Aryeo::Actions
  class ResolveResourceConflict < ApplicationInteractor
    def call
      session = context.fetch(:session)
      name = context.fetch(:resource_name).to_sym
      payload = context.fetch(:payload)
      existing_record = session.existing_external_record(name, payload)
      return context.set(:existing_record, existing_record) unless existing_record&.record.present?

      if session.conflict_resolution == "skip"
        context.set(:skip_resource, true).set(:record, existing_record.record).set(:existing_record, existing_record)
      else
        context.set(:existing_record, existing_record)
      end
    end
  end
end

module Integrations::Aryeo::Actions
  class ArchiveResource < ApplicationInteractor
    def call
      return context if context[:skipped] || context[:record_failed]

      session = context.fetch(:session)
      name = context.fetch(:resource_name)
      payload = context.fetch(:payload)
      status = context[:skip_resource] ? :skipped : :imported
      session.archive_imported_record(name, payload, record: context[:record], sync_status: status)
      context
    end
  end
end

module Integrations::Aryeo::Actions
  class CountResource < ApplicationInteractor
    def call
      return context if context[:skipped] || context[:record_failed]

      session = context.fetch(:session)
      name = context.fetch(:resource_name)
      if context[:skip_resource]
        session.record_conflict!(name, dependency: context[:dependency] == true)
      else
        session.record_imported!(name, dependency: context[:dependency] == true)
      end
      context
    end
  end
end

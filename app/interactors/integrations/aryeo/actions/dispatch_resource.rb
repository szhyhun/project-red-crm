module Integrations::Aryeo::Actions
  class DispatchResource < ApplicationInteractor
    def call
      return context if context[:skipped] || context[:skip_resource]

      record = ::Aryeo::ResourceImporter.call(
        session: context.fetch(:session),
        name: context.fetch(:resource_name),
        payload: context.fetch(:payload)
      )
      context.set(:record, record)
    rescue ActiveRecord::RecordInvalid => error
      session = context.fetch(:session)
      session.record_resource_error!(context.fetch(:resource_name), context.fetch(:payload), error)
      context.set(:record_failed, true)
    end
  end
end

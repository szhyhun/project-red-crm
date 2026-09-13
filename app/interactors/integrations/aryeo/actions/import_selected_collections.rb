module Integrations::Aryeo::Actions
  class ImportSelectedCollections < ApplicationInteractor
    def call
      return context if context[:skipped]

      session = context[:session] || build_session
      context.set(:session, session)
      selected_collections(session).each do |name, endpoint|
        result = import_collection(session, name, endpoint, name == :listings ? session.listing_limit : nil)
        return result if result.failure?
      end

      session.heartbeat!(force: true)
      context
    end

    private

    def build_session
      run = context.fetch(:run)
      ::Aryeo::ImportSession.new(
        run:,
        client: context[:client],
        resources: context[:resources] || run.requested_resources,
        import_start_date: context[:import_start_date] || run.import_start_date,
        import_end_date: context[:import_end_date] || run.import_end_date,
        conflict_resolution: context[:conflict_resolution] || run.conflict_resolution,
        listing_limit: context[:listing_limit],
        skip_resources: context[:skip_resources] || []
      )
    end

    def selected_collections(session)
      session.resource_endpoints.filter_map do |name, endpoint|
        if session.selected_resource?(name)
          [ name, endpoint ]
        else
          session.skip_resource!(name)
          nil
        end
      end
    end

    def import_collection(session, name, endpoint, limit)
      session.prepare_collection!(name)
      count_before = session.count_for(name)
      payloads = fetch_payloads(session, name, endpoint)
      payloads = filter_payloads(session, name, payloads, limit)
      payloads.each do |payload|
        result = Integrations::Aryeo::Organizers::ImportResource.call(
          context: context.set(:resource_name, name).set(:payload, payload).set(:dependency, false)
        )
        return result if result.failure?

        session.heartbeat!
      end
      session.complete_collection!(name, count_before)
      context
    rescue ::Aryeo::Client::EndpointUnavailable => error
      session.mark_endpoint_unavailable!(name, error)
      context
    rescue ::Aryeo::Client::Error => error
      session.mark_endpoint_failed!(name, error)
      context
    ensure
      session.persist_progress!
    end

    def fetch_payloads(session, name, endpoint)
      payloads = []
      session.paginate_resource(name, endpoint) do |payload|
        payloads << session.normalize_payload(payload)
        session.heartbeat!
      end
      payloads
    end

    def filter_payloads(session, name, payloads, limit)
      payloads = payloads.filter_map do |payload|
        filter_reason = session.filter_reason_for(name, payload)
        if filter_reason == :unavailable
          session.record_date_unavailable!(name)
          payload
        elsif filter_reason
          session.record_filtered!(name, filter_reason)
          nil
        else
          payload
        end
      end
      limit ? payloads.sort_by { |payload| session.sort_key_for(payload) }.reverse.first(limit) : payloads
    end
  end
end

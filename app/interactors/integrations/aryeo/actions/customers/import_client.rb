module Integrations::Aryeo::Actions::Customers
  class ImportClient < ApplicationInteractor
      def call
        importer = context.fetch(:importer)
        payload = context.fetch(:payload)
        external = importer.customer_external_id(payload)
        return context.set(:client, nil) if external.blank?

        client = importer.customer_record_for("clients", external)&.record ||
                 importer.organization.client_accounts.find_by("metadata ->> 'aryeo_id' = ?", external)
        client ||= importer.organization.client_accounts.build(metadata: { "aryeo_id" => external })
        client.assign_attributes(
          name: importer.customer_person_name(payload, "company_name").presence || "Aryeo client #{external}",
          email: importer.customer_value(payload, "email", "email_address"),
          phone: importer.customer_value(payload, "phone", "phone_number"),
          brokerage_name: importer.customer_value(payload, "brokerage_name", "company"),
          kind: importer.customer_kind(payload),
          origin: :aryeo,
          metadata: client.metadata.merge("aryeo_id" => external)
        )
        client.save!

        context.set(:client, client)
      end
  end
end

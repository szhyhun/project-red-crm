module Integrations::Aryeo::Actions::Customers
  class ImportTeam < ApplicationInteractor
      def call
        importer = context.fetch(:importer)
        payload = context.fetch(:payload)
        external = importer.customer_external_id(payload)
        return context.set(:team, nil) if external.blank?

        team = importer.customer_record_for("customer_teams", external)&.record
        name = importer.customer_value(payload, "name", "brokerage_name").presence || "Aryeo customer team #{external}"
        team ||= importer.organization.customer_teams.find_by("lower(name) = ?", name.downcase)
        team ||= importer.organization.customer_teams.build
        team.assign_attributes(
          name:,
          brokerage_name: importer.customer_value(payload, "brokerage_name"),
          brokerage_website: importer.customer_value(payload, "brokerage_website"),
          website: importer.customer_value(payload, "website"),
          logo_url: importer.customer_value(payload, "logo_url"),
          description: importer.customer_value(payload, "description"),
          archived: importer.customer_boolean_value(payload, "is_archived"),
          origin: :aryeo
        )
        team.save!

        importer.customer_payloads(payload).each do |customer_payload|
          customer_id = importer.customer_external_id(customer_payload)
          account = importer.customer_record_for("clients", customer_id)&.record
          if customer_id.present? && account.blank? && importer.customer_payload_has_profile?(customer_payload)
            account = importer.customer_import_dependency(:clients, customer_payload)
          end
          team.customer_team_memberships.find_or_create_by!(client_account: account) if account
        end

        context.set(:team, team)
      end
  end
end

namespace :customer_teams do
  desc "Backfill CustomerTeam records from imported Aryeo customer-team payloads"
  task backfill: :environment do
    ExternalRecord.where(resource_type: "customer_teams", record_type: nil).find_each do |external_record|
      payload = external_record.source_payload.stringify_keys
      name = payload["name"].presence || payload["brokerage_name"].presence
      next if name.blank?

      team = external_record.organization.customer_teams.find_or_initialize_by(name: name)
      team.assign_attributes(
        brokerage_name: payload["brokerage_name"],
        brokerage_website: payload["brokerage_website"],
        website: payload["website"],
        logo_url: payload["logo_url"],
        description: payload["description"],
        archived: ActiveModel::Type::Boolean.new.cast(payload["is_archived"]),
        origin: :aryeo
      )
      team.save!
      external_record.update!(record: team, sync_status: :imported, last_imported_at: Time.current)
    end
  end
end

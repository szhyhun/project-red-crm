require "rails_helper"

RSpec.describe Integrations::Aryeo::Actions::Customers::ImportTeam do
  let!(:organization) { Organization.create!(name: "Team Import Agency", slug: "team-import-agency") }
  let!(:connection) do
    IntegrationConnection.create!(organization:, provider: :aryeo, api_key: "aryeo-key", status: :connected)
  end
  let!(:run) do
    connection.integration_import_runs.create!(organization:, provider: :aryeo, requested_resources: %w[clients customer_teams])
  end
  let(:importer) { Aryeo::Importer.new(run:, client: instance_double(Aryeo::Client)) }

  it "creates the team and imports a profiled customer dependency" do
    result = described_class.call(
      importer:,
      payload: {
        "id" => "team-1",
        "name" => "Oak Bay Realty",
        "customer_ids" => [ "customer-1" ],
        "customers" => [ { "id" => "customer-1", "name" => "Avery Agent", "email" => "avery@example.test" } ]
      }
    )

    expect(result).to be_success
    team = result[:team]
    expect(team).to be_aryeo
    expect(team.client_accounts.pluck(:email)).to eq([ "avery@example.test" ])
  end
end

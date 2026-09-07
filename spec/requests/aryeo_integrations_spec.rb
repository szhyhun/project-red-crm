require "rails_helper"

RSpec.describe "Aryeo integrations", type: :request do
  include ActiveJob::TestHelper
  let!(:organization) { Organization.create!(name: "Integration Agency", slug: "integration-agency") }
  let!(:admin) { User.create!(organization:, name: "Admin", email: "aryeo-admin@example.test", password: "long-enough-password", role: :organization_admin) }
  let!(:manager) { User.create!(organization:, name: "Manager", email: "aryeo-manager@example.test", password: "long-enough-password", role: :manager) }

  it "stores an admin-provided key encrypted and never returns it" do
    sign_in admin

    post "/api/v1/aryeo_integration", params: { api_key: "aryeo-live-secret" }

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("aryeo-live-secret")
    connection = organization.integration_connections.find_by!(provider: :aryeo)
    expect(connection.read_attribute_before_type_cast("api_key")).not_to include("aryeo-live-secret")
    expect(JSON.parse(response.body).dig("integration", "api_key_masked")).to end_with("cret")
  end

  it "does not let non-admin staff access organization integrations" do
    sign_in manager

    get "/api/v1/aryeo_integration"

    expect(response).to have_http_status(:forbidden)
  end

  it "disconnects locally without deleting imported records" do
    connection = IntegrationConnection.create!(organization:, provider: :aryeo, api_key: "aryeo-key", status: :connected)
    client = ClientAccount.create!(organization:, name: "Imported", origin: :aryeo)
    ExternalRecord.create!(organization:, integration_connection: connection, provider: :aryeo, resource_type: "clients", external_id: "client-1", record: client)
    sign_in admin

    delete "/api/v1/aryeo_integration"

    expect(response).to have_http_status(:no_content)
    expect(connection.reload).not_to be_api_key_configured
    expect(client.reload).to be_present
  end

  it "queues a selected import with date and conflict controls" do
    connection = IntegrationConnection.create!(organization:, provider: :aryeo, api_key: "aryeo-key", status: :connected)
    sign_in admin

    expect {
      post "/api/v1/aryeo_integration/import", params: {
        resources: %w[clients listings orders],
        import_start_date: "2026-01-01",
        import_end_date: "2026-01-31",
        conflict_resolution: "overwrite"
      }
    }.to have_enqueued_job(AryeoImportJob)

    expect(response).to have_http_status(:accepted)
    run = connection.integration_import_runs.order(:id).last
    expect(run.requested_resources).to eq(%w[clients listings orders])
    expect(run.import_start_date).to eq(Date.new(2026, 1, 1))
    expect(run.import_end_date).to eq(Date.new(2026, 1, 31))
    expect(run.conflict_resolution).to eq("overwrite")
    expect(JSON.parse(response.body).dig("import_run", "import_start_date")).to eq("2026-01-01")
    expect(JSON.parse(response.body).dig("import_run", "import_end_date")).to eq("2026-01-31")
  end

  it "rejects an import date range whose end precedes its start" do
    IntegrationConnection.create!(organization:, provider: :aryeo, api_key: "aryeo-key", status: :connected)
    sign_in admin

    post "/api/v1/aryeo_integration/import", params: {
      resources: [ "listings" ], import_start_date: "2026-02-01", import_end_date: "2026-01-31"
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)).to include("error" => "aryeo_import_date_range_invalid")
  end

  it "rejects an invalid import end date" do
    IntegrationConnection.create!(organization:, provider: :aryeo, api_key: "aryeo-key", status: :connected)
    sign_in admin

    post "/api/v1/aryeo_integration/import", params: {
      resources: [ "listings" ], import_end_date: "not-a-date"
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)).to include("error" => "aryeo_import_end_date_invalid")
  end

  it "requires at least one known resource" do
    IntegrationConnection.create!(organization:, provider: :aryeo, api_key: "aryeo-key", status: :connected)
    sign_in admin

    post "/api/v1/aryeo_integration/import", params: { resources: [ "not-an-aryeo-resource" ] }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)).to include("error" => "aryeo_import_resources_invalid")
  end
end

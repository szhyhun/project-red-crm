require "rails_helper"

RSpec.describe "Aryeo integrations", type: :request do
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
end

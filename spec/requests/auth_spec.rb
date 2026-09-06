require "rails_helper"

RSpec.describe "CRM authentication", type: :request do
  it "creates an organization-owned admin session during sign-up" do
    post "/api/v1/auth/sign_up", params: {
      organization: { name: "North Star Media", slug: "north-star-media" },
      user: { name: "Avery Owner", email: "avery@example.test", password: "long-enough-password", password_confirmation: "long-enough-password" }
    }

    expect(response).to have_http_status(:created)
    expect(Organization.find_by!(slug: "north-star-media").users.find_by!(email: "avery@example.test")).to have_attributes(role: "organization_admin", status: "active")
    expect(JSON.parse(response.body)).to include("csrf_token")
  end

  it "does not create a session for suspended users" do
    organization = Organization.create!(name: "North Star Media", slug: "north-star-media")
    User.create!(organization:, name: "Suspended User", email: "suspended@example.test", password: "long-enough-password", role: :manager, status: :suspended)

    post "/api/v1/auth/sign_in", params: { email: "suspended@example.test", password: "long-enough-password" }

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)).to eq("error" => "invalid_credentials")
  end

  it "publishes role-independent session capabilities" do
    organization = Organization.create!(name: "North Star Media", slug: "north-star-media")
    admin = User.create!(organization:, name: "Avery Owner", email: "avery@example.test",
                         password: "long-enough-password", role: :organization_admin)

    sign_in admin
    get "/api/v1/auth/me"

    capabilities = JSON.parse(response.body).fetch("user").fetch("capabilities")
    expect(capabilities.fetch("dashboard")).to include("view")
    expect(capabilities.fetch("client_portal")).to be_empty
    expect(capabilities.fetch("boards")).to include("create")
    expect(capabilities.fetch("staff")).to include("create", "manage")
    expect(capabilities.fetch("products")).to include("create")
  end

  it "identifies client portal access without exposing the internal dashboard" do
    organization = Organization.create!(name: "North Star Media", slug: "north-star-media")
    client = User.create!(organization:, name: "Avery Client", email: "client@example.test",
                          password: "long-enough-password", role: :client_member)

    sign_in client
    get "/api/v1/auth/me"

    capabilities = JSON.parse(response.body).fetch("user").fetch("capabilities")
    expect(capabilities.fetch("client_portal")).to include("view", "update")
    expect(capabilities.fetch("dashboard")).to be_empty
  end
end

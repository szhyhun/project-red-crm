require "rails_helper"

RSpec.describe "API CORS policy", type: :request do
  let(:crm_origin) { ProjectRed::OriginAllowlist.crm_ui.first }
  let(:public_origin) { ProjectRed::OriginAllowlist.public_site.first }

  it "keeps credentialed API access available to the CRM UI" do
    get "/api/v1/auth/csrf", headers: { "Origin" => crm_origin }

    expect(response).to have_http_status(:ok)
    expect(response.headers["Access-Control-Allow-Origin"]).to eq(crm_origin)
    expect(response.headers["Access-Control-Allow-Credentials"]).to eq("true")
    expect(response.headers["Cache-Control"]).to include("no-store")
  end

  it "does not grant the public site access to session endpoints" do
    get "/api/v1/auth/csrf", headers: { "Origin" => public_origin }

    expect(response).to have_http_status(:ok)
    expect(response.headers).not_to have_key("Access-Control-Allow-Origin")
  end

  it "limits public-site CORS to the public API without credentials" do
    options "/api/v1/public/property_sites/example/site", headers: {
      "Origin" => public_origin,
      "Access-Control-Request-Method" => "GET"
    }

    expect(response).to have_http_status(:ok)
    expect(response.headers["Access-Control-Allow-Origin"]).to eq(public_origin)
    expect(response.headers["Access-Control-Allow-Credentials"]).to be_blank
  end
end

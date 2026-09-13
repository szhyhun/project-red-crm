require "rails_helper"

RSpec.describe Aryeo::ResourceImporter do
  let!(:organization) { Organization.create!(name: "Resource Import Agency", slug: "resource-import-agency") }
  let!(:connection) do
    IntegrationConnection.create!(organization:, provider: :aryeo, api_key: "aryeo-key", status: :connected)
  end
  let!(:run) do
    connection.integration_import_runs.create!(organization:, provider: :aryeo, requested_resources: %w[products clients customer_teams])
  end
  let(:session) { Aryeo::ImportSession.new(run:, client: instance_double(Aryeo::Client)) }

  it "maps an Aryeo product and its variants without creating a package" do
    product = described_class.call(
      session:,
      name: :products,
      payload: {
        "id" => "product-1",
        "type" => "MAIN",
        "title" => "Standard Property Photography",
        "categories" => [ "Photography" ],
        "variants" => [ { "id" => "variant-1", "title" => "0–1,000 sqft", "price_amount" => 29_900 } ]
      }
    )

    expect(product).to have_attributes(kind: "service", deliverable_type: "photography")
    expect(product.product_variants.sole).to have_attributes(price_cents: 29_900, sqft_min: 0, sqft_max: 1_000)
    expect(product.package_components).to be_empty
  end

  it "maps a customer team and its profiled customer dependency" do
    team = described_class.call(
      session:,
      name: :customer_teams,
      payload: {
        "id" => "team-1",
        "name" => "Oak Bay Realty",
        "customer_ids" => [ "customer-1" ],
        "customers" => [ { "id" => "customer-1", "name" => "Avery Agent", "email" => "avery@example.test" } ]
      }
    )

    expect(team).to be_aryeo
    expect(team.client_accounts.pluck(:email)).to eq([ "avery@example.test" ])
  end
end

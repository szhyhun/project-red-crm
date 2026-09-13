require "rails_helper"

RSpec.describe Integrations::Aryeo::Actions::Catalog::ImportProduct do
  let!(:organization) { Organization.create!(name: "Catalog Import Agency", slug: "catalog-import-agency") }
  let!(:connection) do
    IntegrationConnection.create!(organization:, provider: :aryeo, api_key: "aryeo-key", status: :connected)
  end
  let!(:run) do
    connection.integration_import_runs.create!(organization:, provider: :aryeo, requested_resources: [ "products" ])
  end
  let(:importer) { Aryeo::Importer.new(run:, client: instance_double(Aryeo::Client)) }

  it "maps a service and its purchasable variants without creating a package" do
    result = described_class.call(
      importer:,
      payload: {
        "id" => "product-1",
        "type" => "MAIN",
        "title" => "Standard Property Photography",
        "categories" => [ "Photography" ],
        "variants" => [ { "id" => "variant-1", "title" => "0–1,000 sqft", "price_amount" => 29_900 } ]
      }
    )

    expect(result).to be_success
    expect(result[:product]).to have_attributes(kind: "service", deliverable_type: "photography")
    expect(result[:product].product_variants.sole).to have_attributes(price_cents: 29_900, sqft_min: 0, sqft_max: 1_000)
    expect(result[:product].package_components).to be_empty
  end
end

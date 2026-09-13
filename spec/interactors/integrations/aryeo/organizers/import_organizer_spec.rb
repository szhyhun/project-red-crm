require "rails_helper"

RSpec.describe Integrations::Aryeo::Organizers::ImportOrganizer do
  let!(:organization) { Organization.create!(name: "Run Import Agency", slug: "run-import-agency") }
  let!(:connection) do
    IntegrationConnection.create!(organization:, provider: :aryeo, api_key: "aryeo-key", status: :connected)
  end
  let!(:run) do
    connection.integration_import_runs.create!(organization:, provider: :aryeo, requested_resources: [ "products" ])
  end

  it "is only the ordered import workflow" do
    expect(described_class.interactors).to eq([
      Integrations::Aryeo::Actions::StartImport,
      Integrations::Aryeo::Actions::ImportSelectedCollections,
      Integrations::Aryeo::Actions::ReconcileImportedDelivery,
      Integrations::Aryeo::Actions::CompleteImport
    ])
  end

  it "propagates an unexpected child failure without owning terminal state" do
    error = StandardError.new("import exploded")
    allow(Integrations::Aryeo::Actions::StartImport).to receive(:call).and_raise(error)

    expect { described_class.call(run:) }.to raise_error(error)
    expect(run.reload).not_to be_failed
  end
end

require "rails_helper"

RSpec.describe Aryeo::RunImport do
  let!(:organization) { Organization.create!(name: "Run Import Agency", slug: "run-import-agency") }
  let!(:connection) do
    IntegrationConnection.create!(organization:, provider: :aryeo, api_key: "aryeo-key", status: :connected)
  end
  let!(:run) do
    connection.integration_import_runs.create!(organization:, provider: :aryeo, requested_resources: [ "products" ])
  end

  it "returns the reloaded run after the importer completes" do
    importer = instance_double(Aryeo::Importer)
    allow(Aryeo::Importer).to receive(:new).with(
      run:, resources: [ "products" ], import_start_date: nil, import_end_date: nil, conflict_resolution: "skip"
    ).and_return(importer)
    allow(importer).to receive(:call)

    result = described_class.call(run:)

    expect(result).to be_success
    expect(result[:run]).to eq(run.reload)
  end

  it "returns a typed failure and preserves the importer exception" do
    importer = instance_double(Aryeo::Importer)
    error = StandardError.new("import exploded")
    allow(Aryeo::Importer).to receive(:new).and_return(importer)
    allow(importer).to receive(:call).and_raise(error)

    result = described_class.call(run:)

    expect(result).to be_failure
    expect(result.failure.code).to eq("aryeo_import_failed")
    expect(result.failure.original_error).to eq(error)
    expect(run.reload).to be_failed
  end
end

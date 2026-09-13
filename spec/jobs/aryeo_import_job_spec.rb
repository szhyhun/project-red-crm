require "rails_helper"

RSpec.describe AryeoImportJob do
  let!(:organization) { Organization.create!(name: "Import Agency", slug: "import-job-agency") }
  let!(:connection) do
    IntegrationConnection.create!(organization:, provider: :aryeo, api_key: "aryeo-key", status: :connected)
  end
  let!(:run) do
    connection.integration_import_runs.create!(organization:, provider: :aryeo, requested_resources: [ "products" ])
  end

  it "marks the run failed when the importer raises and re-raises the job error" do
    importer = instance_double(Aryeo::Importer)
    allow(Aryeo::Importer).to receive(:new).and_return(importer)
    allow(importer).to receive(:import_collections!).and_raise(StandardError, "catalog database failure")

    expect { described_class.perform_now(run.id) }.to raise_error(StandardError, "catalog database failure")

    expect(run.reload).to be_failed
    expect(run.completed_at).to be_present
    expect(run.error_details).to include("StandardError: catalog database failure")
  end

  it "does not re-run a terminal completed-with-errors result" do
    run.update!(status: :completed_with_errors, phase: "completed", completed_at: Time.current,
                error_details: [ "one record was invalid" ])
    importer = instance_double(Aryeo::Importer)
    allow(Aryeo::Importer).to receive(:new).and_return(importer)
    allow(importer).to receive(:import_collections!).and_raise(StandardError, "late notification failure")

    expect { described_class.perform_now(run.id) }.not_to raise_error

    expect(run.reload).to be_completed_with_errors
    expect(run.error_details).to eq([ "one record was invalid" ])
  end
end

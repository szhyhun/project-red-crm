require "rails_helper"

RSpec.describe "Aryeo import lifecycle interactors", type: :service do
  let!(:organization) { Organization.create!(name: "Lifecycle Agency", slug: "lifecycle-agency") }
  let!(:connection) do
    IntegrationConnection.create!(organization:, provider: :aryeo, api_key: "aryeo-key", status: :connected)
  end
  let!(:run) do
    connection.integration_import_runs.create!(organization:, provider: :aryeo, requested_resources: [ "products" ])
  end

  def importer_state(overrides = {})
    {
      counts: {},
      conflict_counts: {},
      filtered_counts: {},
      filtered_after_counts: {},
      date_unavailable_counts: {},
      dependency_counts: {},
      dependency_conflict_counts: {},
      media_counts: {},
      deferred_skipped_resources: [],
      coverage: {},
      errors: []
    }.merge(overrides)
  end

  it "starts a pending run and marks its integration as importing" do
    result = Integrations::Aryeo::Actions::StartImport.call(run:)

    expect(result).to be_success
    expect(run.reload).to have_attributes(status: "running", phase: "starting")
    expect(run.started_at).to be_present
    expect(connection.reload).to be_status_importing
  end

  it "does not move a terminal run back to running" do
    run.update!(status: :completed, phase: "completed", completed_at: Time.current)

    result = Integrations::Aryeo::Actions::StartImport.call(run:)

    expect(result).to be_success
    expect(result[:skipped]).to be(true)
    expect(run.reload).to be_completed
    expect(connection.reload).to be_status_connected
  end

  it "completes with warnings and records skipped resources and dependency coverage" do
    importer = instance_double(Aryeo::Importer, state: importer_state(
      deferred_skipped_resources: [ "appointments" ],
      dependency_counts: { "clients" => 2 },
      dependency_conflict_counts: { "clients" => 1 },
      errors: [ "one appointment could not be imported" ]
    ))
    run.update!(status: :running, phase: "products")
    connection.update!(status: :importing)

    result = Integrations::Aryeo::Actions::CompleteImport.call(run:, importer:)

    expect(result).to be_success
    expect(run.reload).to be_completed_with_errors
    expect(run.coverage).to include(
      "appointments" => include("status" => "skipped"),
      "clients" => include("status" => "imported_as_dependency", "count" => 2, "skipped_conflicts" => 1)
    )
    expect(connection.reload).to be_status_connected
    expect(connection.last_imported_at).to be_present
  end

  it "marks unexpected failures with a stable error code" do
    run.update!(status: :running, phase: "products")
    error = StandardError.new("database unavailable")
    importer = instance_double(Aryeo::Importer, state: importer_state)

    result = Integrations::Aryeo::Actions::FailImport.call(run:, importer:, error:)

    expect(result).to be_success
    expect(run.reload).to have_attributes(status: "failed", error_code: "import_failure", phase: "failed")
    expect(run.error_details).to include("StandardError: database unavailable")
    expect(run.completed_at).to be_present
  end

  it "classifies an Aryeo client failure as an endpoint failure" do
    run.update!(status: :running, phase: "products")
    error = Aryeo::Client::EndpointUnavailable.new("products is unavailable")

    Integrations::Aryeo::Actions::FailImport.call(run:, error:)

    expect(run.reload).to have_attributes(status: "failed", error_code: "endpoint_failure")
    expect(connection.reload).to be_status_invalid
  end
end

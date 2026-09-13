require "rails_helper"

RSpec.describe Aryeo::FailStaleImports do
  let!(:organization) { Organization.create!(name: "Stale Import Agency", slug: "stale-import-agency") }
  let!(:connection) do
    IntegrationConnection.create!(organization:, provider: :aryeo, api_key: "aryeo-key", status: :importing)
  end

  it "fails stale runs and reconnects an idle integration" do
    now = Time.zone.parse("2026-09-12 12:00:00")
    run = connection.integration_import_runs.create!(
      organization:, provider: :aryeo, status: :running, started_at: now - 20.minutes, heartbeat_at: now - 20.minutes
    )

    result = described_class.call(at: now)

    expect(result).to be_success
    expect(result[:failed_run_ids]).to eq([ run.id ])
    expect(run.reload).to be_failed
    expect(connection.reload).to be_status_connected
  end
end

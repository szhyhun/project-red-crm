require "rails_helper"

RSpec.describe Aryeo::ImportWatchdogJob do
  let!(:organization) { Organization.create!(name: "Watchdog Agency", slug: "watchdog-agency") }
  let!(:connection) do
    IntegrationConnection.create!(organization:, provider: :aryeo, api_key: "aryeo-key", status: :importing)
  end

  it "marks a run failed and releases an idle importing connection" do
    now = Time.zone.parse("2026-09-12 12:00:00")
    run = connection.integration_import_runs.create!(
      organization:, provider: :aryeo, status: :running, phase: "tasks",
      started_at: now - 20.minutes, heartbeat_at: now - 20.minutes
    )

    described_class.perform_now(now)

    expect(run.reload).to be_failed
    expect(run.completed_at).to eq(now)
    expect(run.error_details).to include("Aryeo import worker heartbeat expired at #{now.iso8601}")
    expect(connection.reload).to be_status_connected
  end

  it "keeps an active run running when its heartbeat is fresh" do
    now = Time.zone.parse("2026-09-12 12:00:00")
    run = connection.integration_import_runs.create!(
      organization:, provider: :aryeo, status: :running, phase: "products",
      started_at: now - 2.minutes, heartbeat_at: now - 2.minutes
    )

    described_class.perform_now(now)

    expect(run.reload).to be_running
    expect(connection.reload).to be_status_importing
  end
end

require "rails_helper"

RSpec.describe BoardWorkflowRun, type: :model do
  let!(:organization) { Organization.create!(name: "Run state agency", slug: "run-state-agency") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Run state client", kind: :agent) }
  let!(:order) { Order.create!(organization:, client_account:, payment_mode: :pay_later) }
  let!(:workflow) do
    organization.default_board.board_workflows.create!(organization:, name: "Run state workflow",
                                                        trigger_key: "order_approved", enabled: false)
  end
  let!(:run) do
    workflow.runs.create!(organization:, order:, idempotency_key: "run-state-#{SecureRandom.uuid}",
                          triggered_at: Time.zone.parse("2026-09-08 10:00:00"))
  end

  it "starts pending with no retries and exposes only the documented run states" do
    expect(run).to have_attributes(status: "pending", retry_count: 0)
    expect(described_class.statuses.keys).to contain_exactly(
      "pending", "running", "succeeded", "succeeded_with_warnings", "failed"
    )
  end

  it "accepts every documented lifecycle state" do
    %w[running succeeded succeeded_with_warnings failed].each do |status|
      expect(run.update(status:)).to be(true)
    end

    expect(run).to be_failed
  end

  it "rejects an unknown state and a negative retry count" do
    invalid = described_class.new(organization:, board_workflow: workflow, order:,
                                 idempotency_key: "invalid-run-#{SecureRandom.uuid}", triggered_at: Time.current,
                                 status: "paused", retry_count: -1)

    expect(invalid).not_to be_valid
    expect(invalid.errors.full_messages).to include(
      "Status is not included in the list",
      "Retry count must be greater than or equal to 0"
    )
  end

  it "enforces idempotency at the database boundary" do
    duplicate = run.dup

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "lists the most recently triggered run first" do
    older = workflow.runs.create!(organization:, order:, idempotency_key: "older-run-#{SecureRandom.uuid}",
                                  triggered_at: 2.hours.ago)
    newer = workflow.runs.create!(organization:, order:, idempotency_key: "newer-run-#{SecureRandom.uuid}",
                                  triggered_at: 1.hour.ago)

    expect(described_class.where(id: [ older.id, newer.id ]).recent).to eq([ newer, older ])
  end

  it "requires a workflow and order from the same organization" do
    other_organization = Organization.create!(name: "Other run state agency", slug: "other-run-state-agency")
    foreign_client = ClientAccount.create!(organization: other_organization, name: "Foreign run client", kind: :agent)
    foreign_order = Order.create!(organization: other_organization, client_account: foreign_client,
                                  payment_mode: :pay_later)
    foreign_workflow = other_organization.default_board.board_workflows.create!(
      organization: other_organization, name: "Foreign run workflow", trigger_key: "order_approved", enabled: false
    )
    invalid = described_class.new(organization:, board_workflow: foreign_workflow, order: foreign_order,
                                  idempotency_key: "foreign-run-#{SecureRandom.uuid}", triggered_at: Time.current)

    expect(invalid).not_to be_valid
    expect(invalid.errors.full_messages).to include(
      "Board workflow must belong to the same organization",
      "Order must belong to the same organization"
    )
  end
end

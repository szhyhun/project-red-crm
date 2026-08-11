require "rails_helper"

RSpec.describe Notifications::DeliverJob, type: :job do
  let!(:organization) { Organization.create!(name: "ProjectRed", slug: "projectred") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Avery Agent", kind: :agent, email: "agent@example.test") }
  let!(:invoice) { Invoice.create!(organization:, client_account:, number: "PR-000003", total_cents: 54_900, balance_due_cents: 54_900) }
  let!(:delivery) do
    NotificationDelivery.create!(
      organization:, notifiable: invoice, kind: "invoice_ready", recipient: "agent@example.test",
      deduplication_key: "invoice-ready-3", status: :processing, attempts: 1
    )
  end

  it "does not deliver while another worker owns the processing lease" do
    expect(CustomerNotifications).not_to receive(:deliver_now)

    described_class.perform_now(delivery.id)
  end

  it "retries a stale processing delivery" do
    delivery.update_columns(updated_at: 16.minutes.ago)
    allow(CustomerNotifications).to receive(:deliver_now)

    described_class.perform_now(delivery.id)

    expect(CustomerNotifications).to have_received(:deliver_now).with(delivery)
    expect(delivery.reload).to be_delivered
  end
end

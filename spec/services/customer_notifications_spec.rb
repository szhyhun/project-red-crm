require "rails_helper"

RSpec.describe CustomerNotifications do
  include ActiveJob::TestHelper

  let!(:organization) { Organization.create!(name: "ProjectRed", slug: "projectred") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Avery Agent", kind: :agent, email: "agent@example.test") }

  after { clear_enqueued_jobs }

  it "persists and queues an invoice notification for the client account address" do
    invoice = Invoice.create!(organization:, client_account:, number: "PR-000001", total_cents: 54_900, balance_due_cents: 54_900)

    expect { described_class.invoice_ready(invoice) }
      .to change(NotificationDelivery, :count).by(1)
      .and have_enqueued_job(Notifications::DeliverJob).on_queue("mailers")
    expect(NotificationDelivery.last).to have_attributes(kind: "invoice_ready", recipient: "agent@example.test", status: "pending")
  end

  it "does not block delivery status when a client has no email address" do
    listing = Listing.create!(organization:, client_account: ClientAccount.create!(organization:, name: "No Email", kind: :agent), address_line_1: "111 Oak Bay Avenue")

    expect { described_class.listing_ready(listing) }.not_to raise_error
  end

  it "keeps notification intent when the queue is unavailable" do
    invoice = Invoice.create!(organization:, client_account:, number: "PR-000002", total_cents: 54_900, balance_due_cents: 54_900)
    allow(Notifications::DeliverJob).to receive(:perform_later).and_raise(Redis::CannotConnectError)

    expect { described_class.invoice_ready(invoice) }.to change(NotificationDelivery, :count).by(1)
    expect(NotificationDelivery.last).to be_pending
  end
end

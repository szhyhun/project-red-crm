require "rails_helper"

RSpec.describe "Listing operations", type: :request do
  let!(:organization) { Organization.create!(name: "ProjectRed", slug: "projectred") }
  let!(:manager) { User.create!(organization:, name: "Morgan Manager", email: "morgan@example.test", password: "long-enough-password", role: :manager) }
  let!(:client) { ClientAccount.create!(organization:, name: "Avery Agent", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account: client, address_line_1: "111 Oak Bay Avenue", city: "Victoria", province: "BC") }

  before { sign_in manager }

  it "keeps the production board scoped to the signed-in organization" do
    own_task = WorkflowTask.create!(organization:, listing:, title: "Edit hero video", stage: "editing")
    other_organization = Organization.create!(name: "Other Agency", slug: "other-agency")
    other_client = ClientAccount.create!(organization: other_organization, name: "Other Agent", kind: :agent)
    other_listing = Listing.create!(organization: other_organization, client_account: other_client, address_line_1: "100 Other Street")
    WorkflowTask.create!(organization: other_organization, listing: other_listing, title: "Hidden task", stage: "editing")

    get "/api/v1/workflow_tasks"

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).fetch("workflow_tasks").map { |task| task.fetch("id") }).to eq([own_task.id])
  end

  it "rejects an appointment assigned to staff from another organization" do
    other_organization = Organization.create!(name: "Other Agency", slug: "other-agency")
    other_user = User.create!(organization: other_organization, name: "Other Staff", email: "other@example.test", password: "long-enough-password", role: :production_staff)

    post "/api/v1/listings/#{listing.id}/appointments", params: {
      appointment: { assigned_user_id: other_user.id, starts_at: 1.day.from_now, ends_at: 1.day.from_now + 2.hours }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body).dig("details", "assigned_user")).to include("must belong to the same organization")
  end

  it "does not expose another organization's listing" do
    other_organization = Organization.create!(name: "Other Agency", slug: "other-agency")
    other_client = ClientAccount.create!(organization: other_organization, name: "Other Agent", kind: :agent)
    other_listing = Listing.create!(organization: other_organization, client_account: other_client, address_line_1: "100 Other Street")

    get "/api/v1/listings/#{other_listing.id}"

    expect(response).to have_http_status(:not_found)
  end

  it "does not reactivate a paid invoice by sending it again" do
    invoice = Invoice.create!(organization:, client_account: client, listing:, number: "PR-PAID", status: :paid, total_cents: 35_000, balance_due_cents: 0)

    post "/api/v1/invoices/#{invoice.id}/send_invoice"

    expect(response).to have_http_status(:unprocessable_entity)
    expect(invoice.reload).to be_paid
  end
end

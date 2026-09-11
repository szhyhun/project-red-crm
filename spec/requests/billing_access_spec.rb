require "rails_helper"

# Customer billing belongs to the people who handle money. A production
# specialist works on an order but must not read what it cost, whether through
# invoices directly or through money fields riding along on orders and listings.
RSpec.describe "Billing access", type: :request do
  let!(:organization) { Organization.create!(name: "ProjectRed", slug: "projectred-billing-access") }
  let!(:manager) { staff("billing-manager@example.test", :manager) }
  let!(:specialist) { staff("billing-specialist@example.test", :production_staff) }
  let!(:client) { ClientAccount.create!(organization:, name: "Avery Agent", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account: client, address_line_1: "111 Oak Bay Avenue") }
  let!(:order) do
    Order.create!(organization:, client_account: client, listing:, status: :approved,
                  subtotal_cents: 35_000, total_cents: 35_000)
  end
  let!(:invoice) do
    Invoice.create!(organization:, client_account: client, listing:, order:, number: "PR-1001",
                    status: :sent, total_cents: 35_000, balance_due_cents: 35_000)
  end

  def staff(email, role)
    User.create!(organization:, name: email.split("@").first, email:, password: "long-enough-password", role:)
  end

  def body
    JSON.parse(response.body)
  end

  describe "a production specialist" do
    before { sign_in specialist }

    it "sees no invoices" do
      get "/api/v1/invoices"

      expect(response).to have_http_status(:ok)
      expect(body.fetch("invoices")).to be_empty
    end

    it "cannot send an invoice" do
      post "/api/v1/invoices/#{invoice.id}/send_invoice"

      expect(response.status).to be >= 400
      expect(invoice.reload.status).to eq("sent")
    end

    it "sees the order's work but none of its money" do
      get "/api/v1/orders/#{order.id}"

      payload = body.fetch("order")
      expect(payload).to include("id" => order.id)
      expect(payload.keys).not_to include("total_cents", "balance_due_cents", "payment_status", "invoices")
      expect(payload.fetch("items")).to all(satisfy { |item| !item.key?("unit_price_cents") && !item.key?("total_cents") })
    end

    it "sees a listing without its payment status or order total" do
      get "/api/v1/listings/#{listing.id}"

      payload = body.fetch("listing")
      expect(payload["payment_status"]).to be_nil
      expect(payload.dig("order")&.keys).not_to include("total_cents")
    end

    it "cannot learn payment status by filtering listings on it" do
      Listing.create!(organization:, client_account: client, address_line_1: "22 Unpaid Road")

      get "/api/v1/listings", params: { payment_status: "paid" }

      # Invoice PR-1001 is unpaid, so a working filter would return nothing.
      # Ignored for a specialist, it returns every listing.
      expect(response).to have_http_status(:ok)
      expect(body.fetch("listings").length).to eq(2)
    end

    it "is told by the session that billing is not theirs" do
      get "/api/v1/auth/me"

      expect(body.dig("user", "capabilities", "invoices")).not_to include("view")
    end
  end

  describe "a manager" do
    before { sign_in manager }

    it "sees invoices and the money on orders" do
      get "/api/v1/invoices"
      expect(body.fetch("invoices").pluck("id")).to include(invoice.id)

      get "/api/v1/orders/#{order.id}"
      expect(body.fetch("order")).to include("total_cents" => 35_000)
      expect(body.dig("order", "invoices").pluck("id")).to include(invoice.id)
    end

    it "is told by the session that billing is theirs" do
      get "/api/v1/auth/me"

      expect(body.dig("user", "capabilities", "invoices")).to include("view")
    end
  end
end

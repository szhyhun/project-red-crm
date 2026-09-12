require "rails_helper"

RSpec.describe "Client account settings", type: :request do
  let!(:organization) { Organization.create!(name: "Settings agency", slug: "settings-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Settings manager", email: "settings-manager@example.test",
                 password: "long-enough-password", role: :organization_admin)
  end
  let!(:account) { ClientAccount.create!(organization:, name: "Locked Team", kind: :team) }
  let!(:client_user) do
    User.create!(organization:, name: "Locked customer", email: "locked-customer@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account: account, user:, role: :admin, status: :active, is_default: true)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account: account, address_line_1: "Locked Download Street") }
  let!(:order) do
    Order.create!(organization:, client_account: account, listing:, status: :approved, approved_at: Time.current,
                  payment_mode: :pay_later)
  end
  let!(:invoice) do
    Invoice.create!(organization:, client_account: account, listing:, order:, number: "INV-LOCK-1", status: :sent,
                    due_on: Date.current + 7, subtotal_cents: 20_000, total_cents: 20_000,
                    balance_due_cents: 20_000)
  end
  let!(:asset) do
    listing.media_assets.create!(organization:, kind: :final, status: :ready,
                                 storage_key: "settings/#{listing.id}/front.jpg", filename: "front.jpg",
                                 content_type: "image/jpeg", byte_size: 12, category: "images",
                                 customer_visible: true)
  end

  before do
    # The download path streams the file, so one has to exist for a permitted
    # request to get past authorization.
    DeliveryStorage.write(upload: StringIO.new("image bytes"), key: asset.storage_key)
  end

  it "refuses a customer the download while their team locks it and the listing owes money" do
    account.update!(lock_downloads_before_payment: true)
    sign_in client_user

    get "/api/v1/media_assets/#{asset.id}/download"
    expect(response).to have_http_status(:forbidden)

    # Seeing it is a different permission, and stays available.
    get "/api/v1/media_assets/#{asset.id}/preview"
    expect(response).to have_http_status(:ok)
  end

  it "allows the download once the balance is settled" do
    account.update!(lock_downloads_before_payment: true)
    invoice.update!(balance_due_cents: 0, status: :paid)
    sign_in client_user

    get "/api/v1/media_assets/#{asset.id}/download"

    expect(response).to have_http_status(:ok)
  end

  it "never locks staff out of a download" do
    account.update!(lock_downloads_before_payment: true)
    sign_in manager

    get "/api/v1/media_assets/#{asset.id}/download"

    expect(response).to have_http_status(:ok)
  end

  it "leaves a team that does not lock downloads alone" do
    sign_in client_user

    get "/api/v1/media_assets/#{asset.id}/download"

    expect(response).to have_http_status(:ok)
  end

  it "stores the team's identity and settings, and keeps an affiliate code unique" do
    sign_in manager

    patch "/api/v1/client_accounts/#{account.id}", params: {
      client_account: {
        description: "Coast team", internal_note: "Pays late", website: "https://team.example",
        brokerage_website: "https://brokerage.example", affiliate_id: "COAST",
        lock_downloads_before_payment: true, display_original_price: false, suppress_payment_reminders: true
      }
    }

    expect(response).to have_http_status(:ok)
    expect(account.reload).to have_attributes(
      description: "Coast team", internal_note: "Pays late", affiliate_id: "COAST",
      lock_downloads_before_payment: true, display_original_price: false, suppress_payment_reminders: true
    )
    expect(response.parsed_body.dig("client_account", "member_count")).to eq(1)

    other = ClientAccount.create!(organization:, name: "Other team", kind: :team)
    patch "/api/v1/client_accounts/#{other.id}", params: { client_account: { affiliate_id: "COAST" } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(other.reload.affiliate_id).to be_nil
  end

  it "does not let a customer change their own team's settings" do
    sign_in client_user

    patch "/api/v1/client_accounts/#{account.id}", params: {
      client_account: { lock_downloads_before_payment: true }
    }

    expect(response).to have_http_status(:forbidden)
    expect(account.reload.lock_downloads_before_payment).to be(false)
  end
end

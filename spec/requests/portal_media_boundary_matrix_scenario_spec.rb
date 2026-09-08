require "rails_helper"

RSpec.describe "Portal media authorization matrix", type: :request do
  let!(:organization) { Organization.create!(name: "Portal matrix agency", slug: "portal-matrix-agency") }
  let!(:other_organization) { Organization.create!(name: "Other portal matrix agency", slug: "other-portal-matrix-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Portal matrix manager", email: "portal-matrix-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Portal matrix client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Portal matrix customer", email: "portal-matrix-client@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "21 Portal Matrix Street") }
  let!(:service) do
    organization.products.create!(slug: "portal-matrix-service", title: "Portal matrix photography", kind: :service,
                                  deliverable_type: "photography")
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 25_000) }
  let!(:order) do
    Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later, status: :approved,
                  approved_at: Time.current).tap do |record|
      record.order_items.create!(product: service, product_variant: variant, title: service.title, quantity: 1,
                                 unit_price_cents: variant.price_cents, total_cents: variant.price_cents)
    end
  end
  let!(:deliverable) { Orders::DeliverableMaterializer.new(order:).call.sole }

  before do
    visible_asset
    hidden_asset
    pending_asset
    sign_in client_user
  end

  it "shows only current ready final visible media with API-relative paths" do
    get "/api/v1/portal/listings/#{listing.id}/media"

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body
    portal_deliverable = payload.fetch("deliverables").sole
    expect(portal_deliverable).to include("asset_count" => 1)
    expect(portal_deliverable.fetch("assets")).to contain_exactly(
      hash_including(
        "id" => visible_asset.id,
        "preview_path" => "/api/v1/media_assets/#{visible_asset.id}/preview",
        "download_path" => "/api/v1/media_assets/#{visible_asset.id}/download"
      )
    )
    expect(portal_deliverable.fetch("assets").sole).not_to have_key("storage_key")
  end

  it "does not let a customer read another organization's listing media" do
    foreign_account = ClientAccount.create!(organization: other_organization, name: "Foreign matrix client", kind: :agent)
    foreign_listing = Listing.create!(organization: other_organization, client_account: foreign_account,
                                      address_line_1: "99 Hidden Matrix Street")

    get "/api/v1/portal/listings/#{foreign_listing.id}/media"

    expect(response).to have_http_status(:not_found)
  end

  it "does not let a customer read a deliverable from another organization" do
    foreign_account = ClientAccount.create!(organization: other_organization, name: "Foreign deliverable client", kind: :agent)
    foreign_listing = Listing.create!(organization: other_organization, client_account: foreign_account,
                                      address_line_1: "100 Hidden Matrix Street")
    foreign_service = other_organization.products.create!(slug: "foreign-matrix-service", title: "Foreign photography",
                                                           kind: :service, deliverable_type: "photography")
    foreign_variant = foreign_service.product_variants.create!(title: "Standard", price_cents: 10_000)
    foreign_order = Order.create!(organization: other_organization, client_account: foreign_account,
                                  listing: foreign_listing, payment_mode: :pay_later, status: :approved,
                                  approved_at: Time.current)
    foreign_item = foreign_order.order_items.create!(product: foreign_service, product_variant: foreign_variant,
                                                     title: foreign_service.title, quantity: 1,
                                                     unit_price_cents: 10_000, total_cents: 10_000)
    foreign_deliverable = foreign_order.order_deliverables.create!(organization: other_organization,
                                                                    listing: foreign_listing, order: foreign_order,
                                                                    order_item: foreign_item,
                                                                    service_product: foreign_service,
                                                                    title: foreign_service.title,
                                                                    deliverable_type: "photography", sla_days: 0,
                                                                    materialization_key: "foreign-matrix-#{SecureRandom.uuid}")

    get "/api/v1/order_deliverables/#{foreign_deliverable.id}"

    expect(response).to have_http_status(:not_found)
  end

  it "does not allow a customer to request changes for an unfinished deliverable" do
    deliverable.update!(status: :in_progress)

    expect {
      post "/api/v1/portal/listings/#{listing.id}/deliverables/#{deliverable.id}/change_requests", params: {
        change_request: { body: "Please change this before delivery." }
      }
    }.not_to change(Message, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch("error")).to eq("change_requests_only_for_delivered_work")
  end

  private

  def media_attributes(filename:, status: :ready, customer_visible: true)
    {
      organization:, listing:, order:, order_item: order.order_items.sole, order_deliverable: deliverable,
      kind: :final, status:, storage_key: "portal-matrix/#{filename}", filename:, content_type: "image/jpeg",
      byte_size: 5, customer_visible:
    }
  end

  def visible_asset
    @visible_asset ||= deliverable.media_assets.create!(media_attributes(filename: "visible.jpg"))
  end

  def hidden_asset
    @hidden_asset ||= deliverable.media_assets.create!(media_attributes(filename: "hidden.jpg", customer_visible: false))
  end

  def pending_asset
    @pending_asset ||= deliverable.media_assets.create!(media_attributes(filename: "pending.jpg", status: :pending))
  end
end

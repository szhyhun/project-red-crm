require "rails_helper"
require "tempfile"

RSpec.describe "Media delivery ordering API scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Ordering scenario agency", slug: "ordering-scenario-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Ordering manager", email: "ordering-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Ordering client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "40 Ordering Street") }
  let!(:other_listing) { Listing.create!(organization:, client_account:, address_line_1: "41 Ordering Street") }
  let!(:service) do
    organization.products.create!(slug: "ordering-service", title: "Ordering photography", kind: :service,
                                  deliverable_type: "photography")
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 20_000) }
  let!(:first_deliverable) { create_deliverable("first") }
  let!(:second_deliverable) { create_deliverable("second") }

  before { sign_in manager }

  it "keeps unassigned reorders separate from deliverable media" do
    attached = create_asset(first_deliverable, "attached.jpg", position: 7)
    first_unassigned = create_unassigned_asset("first-unassigned.jpg", position: 4)
    second_unassigned = create_unassigned_asset("second-unassigned.jpg", position: 5)

    post "/api/v1/media_assets/reorder", params: {
      listing_id: listing.id,
      category: "images",
      asset_ids: [ second_unassigned.id, first_unassigned.id ]
    }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("media_assets").pluck("id")).to eq([ second_unassigned.id, first_unassigned.id ])
    expect(listing.media_assets.where(order_deliverable_id: nil).order(:position).pluck(:id)).to eq(
      [ second_unassigned.id, first_unassigned.id ]
    )
    expect(attached.reload.position).to eq(7)
  end

  it "rejects an unassigned reorder that tries to include a deliverable asset" do
    attached = create_asset(first_deliverable, "attached-only.jpg", position: 2)
    unassigned = create_unassigned_asset("unassigned-only.jpg", position: 3)

    post "/api/v1/media_assets/reorder", params: {
      listing_id: listing.id,
      category: "images",
      asset_ids: [ unassigned.id, attached.id ]
    }

    expect(response).to have_http_status(:not_found)
    expect(unassigned.reload.position).to eq(3)
    expect(attached.reload.position).to eq(2)
  end

  it "calculates upload positions independently inside each deliverable" do
    allow(MediaAssets::VerifyUploadJob).to receive(:perform_later)
    uploads = [
      upload_for("first-deliverable.jpg", "first delivery"),
      upload_for("second-deliverable.jpg", "second delivery")
    ]

    post "/api/v1/media_assets/upload", params: {
      listing_id: listing.id,
      order_deliverable_id: first_deliverable.id,
      category: "images",
      file: uploads[0].last
    }
    expect(response).to have_http_status(:created)

    post "/api/v1/media_assets/upload", params: {
      listing_id: listing.id,
      order_deliverable_id: second_deliverable.id,
      category: "images",
      file: uploads[1].last
    }
    expect(response).to have_http_status(:created)

    expect(first_deliverable.media_assets.order(:position).pluck(:position)).to eq([ 1 ])
    expect(second_deliverable.media_assets.order(:position).pluck(:position)).to eq([ 1 ])
    expect(MediaAssets::VerifyUploadJob).to have_received(:perform_later).twice
  ensure
    uploads&.each { |tempfile, _file| tempfile.close! }
  end

  private

  def create_deliverable(key)
    order = Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later,
                          status: :approved, approved_at: Time.current)
    item = order.order_items.create!(product: service, product_variant: variant, title: service.title, quantity: 1,
                                     unit_price_cents: variant.price_cents, total_cents: variant.price_cents)
    order.order_deliverables.create!(organization:, listing:, order:, order_item: item, service_product: service,
                                     title: service.title, deliverable_type: service.deliverable_type, sla_days: 0,
                                     position: key == "first" ? 0 : 1,
                                     materialization_key: "ordering-#{key}-#{SecureRandom.uuid}")
  end

  def create_asset(deliverable, filename, position:)
    deliverable.media_assets.create!(organization:, listing:, order: deliverable.order,
                                     order_item: deliverable.order_item, kind: :final, status: :ready,
                                     category: "images", source_url: "https://cdn.example.test/#{filename}",
                                     filename:, content_type: "image/jpeg", byte_size: 5, position:)
  end

  def create_unassigned_asset(filename, position:)
    listing.media_assets.create!(organization:, kind: :final, status: :ready, category: "images",
                                 source_url: "https://cdn.example.test/#{filename}", filename:,
                                 content_type: "image/jpeg", byte_size: 5, position:)
  end

  def upload_for(filename, contents)
    tempfile = Tempfile.new([ filename.delete_suffix(".jpg"), ".jpg" ])
    tempfile.write(contents)
    tempfile.rewind
    [ tempfile, Rack::Test::UploadedFile.new(tempfile.path, "image/jpeg", true, original_filename: filename) ]
  end
end

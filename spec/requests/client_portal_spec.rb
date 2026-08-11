require "rails_helper"

RSpec.describe "Client portal", type: :request do
  it "returns only the signed-in client's listing delivery data" do
    organization = Organization.create!(name: "ProjectRed", slug: "projectred")
    own_account = ClientAccount.create!(organization: organization, name: "Avery Agent", kind: :agent)
    other_account = ClientAccount.create!(organization: organization, name: "Other Agent", kind: :agent)
    client_user = User.create!(organization: organization, name: "Avery Client", email: "avery-client@example.test", password: "long-enough-password", role: :client_admin)
    ClientMembership.create!(client_account: own_account, user: client_user, role: :admin)
    own_listing = Listing.create!(organization: organization, client_account: own_account, address_line_1: "111 Oak Bay Avenue")
    Listing.create!(organization: organization, client_account: other_account, address_line_1: "100 Hidden Street")
    own_listing.workflow_tasks.create!(organization: organization, title: "Edit photos", stage: "editing", customer_visible: true)
    own_listing.workflow_tasks.create!(organization: organization, title: "Internal QA", stage: "review", customer_visible: false)
    MediaAsset.create!(organization: organization, listing: own_listing, kind: :final, status: :ready, storage_key: "final/photo.jpg", filename: "photo.jpg", content_type: "image/jpeg")

    sign_in client_user
    get "/api/v1/client_portal"

    expect(response).to have_http_status(:ok)
    listing = JSON.parse(response.body).fetch("listings").sole
    expect(listing.fetch("address")).to eq("111 Oak Bay Avenue")
    expect(listing.fetch("progress").map { |task| task.fetch("title") }).to eq(["Edit photos"])
    expect(listing.fetch("media_assets").map { |asset| asset.fetch("storage_key") }).to eq(["final/photo.jpg"])
  end
end

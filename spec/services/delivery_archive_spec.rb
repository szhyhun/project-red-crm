require "rails_helper"

RSpec.describe DeliveryArchive, type: :service do
  let(:organization) { Organization.create!(name: "Archive Agency", slug: "archive-agency") }
  let(:manager) { User.create!(organization:, name: "Manager", email: "archive@example.test", password: "long-enough-password", role: :manager) }
  let(:client) { ClientAccount.create!(organization:, name: "Agent", email: "archive-client@example.test", kind: :agent) }
  let(:listing) { Listing.create!(organization:, client_account: client, address_line_1: "111 Oak Bay Avenue") }

  before do
    stub_const("DeliveryStorage::ROOT", Rails.root.join("tmp", "test-deliveries"))
    FileUtils.rm_rf(DeliveryStorage::ROOT)
    FileUtils.mkdir_p(DeliveryStorage::ROOT)
  end

  after { FileUtils.rm_rf(DeliveryStorage::ROOT) }

  it "archives ready visible media by category and skips hidden or unfinished assets" do
    visible = MediaAsset.create!(organization:, listing:, uploaded_by: manager, kind: :final, status: :ready,
                                 category: "images", storage_key: "visible.jpg", filename: "visible.jpg", content_type: "image/jpeg", customer_visible: true)
    hidden = MediaAsset.create!(organization:, listing:, uploaded_by: manager, kind: :final, status: :ready,
                               category: "images", storage_key: "hidden.jpg", filename: "hidden.jpg", content_type: "image/jpeg", hidden: true)
    MediaAsset.create!(organization:, listing:, uploaded_by: manager, kind: :final, status: :pending,
                       category: "videos", storage_key: "pending.mp4", filename: "pending.mp4", content_type: "video/mp4")
    File.binwrite(DeliveryStorage.path_for(visible.storage_key), "image bytes")
    File.binwrite(DeliveryStorage.path_for(hidden.storage_key), "hidden bytes")

    archive = described_class.new(listing).build
    entries = Gem::Package::TarReader.new(archive).map { |entry| [ entry.full_name, entry.read ] }

    expect(entries).to eq([ [ "images/visible.jpg", "image bytes" ] ])
  ensure
    archive&.close!
  end
end

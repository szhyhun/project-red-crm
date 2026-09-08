require "rails_helper"

RSpec.describe MessageMediaReference, type: :model do
  let!(:organization) { Organization.create!(name: "Message reference agency", slug: "message-reference-agency") }
  let!(:other_organization) { Organization.create!(name: "Other message reference agency", slug: "other-message-reference-agency") }
  let!(:author) do
    User.create!(organization:, name: "Reference author", email: "message-reference-author@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Reference client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "1 Reference Street") }
  let!(:other_listing) { Listing.create!(organization:, client_account:, address_line_1: "2 Reference Street") }
  let!(:service) do
    organization.products.create!(slug: "reference-service", title: "Reference photography", kind: :service,
                                  deliverable_type: "photography")
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 10_000) }
  let!(:order) { Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later) }
  let!(:order_item) do
    order.order_items.create!(product: service, product_variant: variant, title: service.title, quantity: 1,
                              unit_price_cents: variant.price_cents, total_cents: variant.price_cents)
  end
  let!(:deliverable) do
    order.order_deliverables.create!(organization:, listing:, order_item:, service_product: service,
                                     title: service.title, deliverable_type: service.deliverable_type,
                                     materialization_key: "reference-deliverable-#{SecureRandom.uuid}")
  end
  let!(:other_deliverable) do
    order.order_deliverables.create!(organization:, listing:, order_item:, service_product: service,
                                     title: "Another #{service.title}", deliverable_type: service.deliverable_type,
                                     materialization_key: "other-reference-deliverable-#{SecureRandom.uuid}")
  end
  let!(:conversation) do
    Conversation.create!(organization:, kind: :internal, subject: "Reference room").tap do |room|
      room.conversation_memberships.create!(user: author, role: :manager)
    end
  end
  let!(:message) { conversation.messages.create!(author:, body: "Please review this image", listing:, order_deliverable: deliverable) }

  def asset_for(listing:, deliverable: nil, organization:)
    source_order = deliverable&.order || (listing.id == order.listing_id ? order : Order.create!(
      organization:, client_account: listing.client_account, listing:, payment_mode: :pay_later
    ))
    source_item = deliverable&.order_item || source_order.order_items.create!(
      product: service, product_variant: variant, title: service.title, quantity: 1,
      unit_price_cents: variant.price_cents, total_cents: variant.price_cents
    )

    MediaAsset.create!(organization:, listing:, order: source_order, order_item: source_item,
                       order_deliverable: deliverable,
                       kind: :final, status: :ready, source_url: "https://cdn.example.test/#{SecureRandom.uuid}.jpg",
                       filename: "reference.jpg", content_type: "image/jpeg", byte_size: 5)
  end

  it "accepts a reference to a ready asset in the message deliverable" do
    asset = asset_for(listing:, deliverable:, organization:)

    reference = message.message_media_references.build(media_asset: asset, position: 0)

    expect(reference).to be_valid
  end

  it "rejects an asset from another listing when the message has listing context" do
    asset = asset_for(listing: other_listing, organization:)
    listing_message = conversation.messages.create!(author:, body: "Please review this listing", listing:)

    reference = listing_message.message_media_references.build(media_asset: asset, position: 0)

    expect(reference).not_to be_valid
    expect(reference.errors.full_messages).to include("Media asset must belong to the message listing")
  end

  it "rejects an asset from another deliverable even when it is on the same listing" do
    asset = asset_for(listing:, deliverable: other_deliverable, organization:)

    reference = message.message_media_references.build(media_asset: asset, position: 0)

    expect(reference).not_to be_valid
    expect(reference.errors.full_messages).to include("Media asset must belong to the message deliverable")
  end

  it "rejects a reference from another organization" do
    foreign_client = ClientAccount.create!(organization: other_organization, name: "Foreign reference client", kind: :agent)
    foreign_listing = Listing.create!(organization: other_organization, client_account: foreign_client,
                                      address_line_1: "Foreign Reference Street")
    foreign_order = Order.create!(organization: other_organization, client_account: foreign_client,
                                  listing: foreign_listing, payment_mode: :pay_later)
    foreign_item = foreign_order.order_items.create!(title: "Foreign reference service", quantity: 1,
                                                      unit_price_cents: 1, total_cents: 1)
    asset = MediaAsset.create!(organization: other_organization, listing: foreign_listing, order: foreign_order,
                               order_item: foreign_item, kind: :final, status: :ready,
                               source_url: "https://cdn.example.test/foreign-reference.jpg",
                               filename: "foreign-reference.jpg", content_type: "image/jpeg", byte_size: 5)

    reference = message.message_media_references.build(media_asset: asset, position: 0)

    expect(reference).not_to be_valid
    expect(reference.errors.full_messages).to include("message and media asset must belong to the same organization")
  end

  it "prevents the same asset from being referenced twice by one message" do
    asset = asset_for(listing:, deliverable:, organization:)
    message.message_media_references.create!(media_asset: asset, position: 0)
    duplicate = message.message_media_references.build(media_asset: asset, position: 1)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors.full_messages).to include("Media asset has already been taken")
    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end

require "rails_helper"

RSpec.describe "media workflow domain rules" do
  let!(:organization) { Organization.create!(name: "Rules Agency", slug: "rules-agency") }
  let!(:other_organization) { Organization.create!(name: "Other Rules Agency", slug: "other-rules-agency") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Rules Client", kind: :agent) }
  let!(:other_client_account) { ClientAccount.create!(organization: other_organization, name: "Other Client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "6 Rules Street") }
  let!(:service) do
    Product.create!(organization:, slug: "rules-service", title: "Rules photography", kind: :service,
                    deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 20_000) }
  let!(:order) { Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later) }
  let!(:order_item) do
    order.order_items.create!(product: service, product_variant: variant, title: "Photography", quantity: 1,
                              unit_price_cents: 20_000, total_cents: 20_000)
  end
  let!(:deliverable) do
    OrderDeliverable.create!(organization:, listing:, order:, order_item:, service_product: service,
                             title: "Photography", deliverable_type: "photography", sla_days: 2,
                             materialization_key: "rules-deliverable")
  end

  it "defaults conversations to two months and supports the permanent retention choices" do
    conversation = Conversation.create!(organization:, kind: :internal, subject: "Retention")

    expect(conversation).to be_two_months
    expect(conversation.retention_days).to eq(60)
    expect(conversation.retention_cutoff).to be_within(2.seconds).of(60.days.ago)
    expect(Conversation.retention_periods.keys).to contain_exactly("two_months", "six_months", "one_year", "forever")
    expect(Conversation.new).not_to respond_to(:one_day?)
  end

  it "does not allow a deliverable to use an item from another order" do
    other_order = Order.create!(organization:, client_account:, payment_mode: :pay_later)
    other_item = other_order.order_items.create!(title: "Other item", quantity: 1,
                                                 unit_price_cents: 1_000, total_cents: 1_000)
    invalid = deliverable.dup
    invalid.materialization_key = "rules-invalid-order-item"
    invalid.order_item = other_item

    expect(invalid).not_to be_valid
    expect(invalid.errors.full_messages).to include("Order item must belong to the order")
  end

  it "does not allow media to link records across order lineage" do
    other_order = Order.create!(organization:, client_account:, payment_mode: :pay_later)
    other_item = other_order.order_items.create!(title: "Other item", quantity: 1,
                                                 unit_price_cents: 1_000, total_cents: 1_000)
    asset = MediaAsset.new(organization:, listing:, order:, order_item: other_item, order_deliverable: deliverable,
                           kind: :final, status: :ready, storage_key: "rules/invalid.jpg", filename: "invalid.jpg",
                           content_type: "image/jpeg")

    expect(asset).not_to be_valid
    expect(asset.errors.full_messages).to include("Order item must belong to the selected order")
    expect(asset.errors.full_messages).to include("Order item must match the deliverable item")
  end

  it "keeps placement columns scoped to their own board" do
    first_board = organization.default_board
    second_board = organization.boards.create!(name: "Rules Internal", kind: :internal, visibility: :organization,
                                                requires_listing: false, client_visible: false, position: 1)
    WorkflowColumn::DEFAULTS.each { |attributes| second_board.workflow_columns.create!(attributes.merge(organization:)) }
    task = second_board.workflow_tasks.build(organization:, title: "Rules task", status: "todo")
    placement = task.workflow_task_placements.build(board: second_board,
                                                    workflow_column: first_board.workflow_columns.find_by!(key: "todo"),
                                                    position: 0)

    expect(placement).not_to be_valid
    expect(placement.errors.full_messages).to include("Workflow column must belong to the selected board")
  end

  it "keeps task and deliverable associations inside one organization" do
    board = organization.boards.create!(name: "Rules Tasks", kind: :internal, visibility: :organization,
                                         requires_listing: false, client_visible: false, position: 1)
    WorkflowColumn::DEFAULTS.each { |attributes| board.workflow_columns.create!(attributes.merge(organization:)) }
    task = board.workflow_tasks.create!(organization:, title: "Rules task", status: "todo")
    other_deliverable = OrderDeliverable.new(
      organization: other_organization,
      order: Order.new(organization: other_organization, client_account: other_client_account),
      order_item: OrderItem.new(title: "Other", quantity: 1, unit_price_cents: 1, total_cents: 1),
      service_product: Product.new(organization: other_organization, slug: "other-rules-service", title: "Other",
                                   kind: :service, deliverable_type: "video"),
      title: "Other", deliverable_type: "video", sla_days: 1, materialization_key: "other-rules-deliverable"
    )
    link = task.workflow_task_deliverables.build(order_deliverable: other_deliverable, position: 0)

    expect(link).not_to be_valid
    expect(link.errors.full_messages).to include("task and deliverable must belong to the same organization")
  end

  it "does not allow a message to reference media from another organization" do
    message = Conversation.create!(organization:, kind: :internal, subject: "Media reference")
      .messages.build(author: nil, body: "reference")
    message.author = User.new(organization:, name: "Rules Author", email: "rules-author@example.test",
                              password: "long-enough-password", role: :manager)
    message.save!
    other_listing = Listing.create!(organization: other_organization, client_account: other_client_account,
                                    address_line_1: "Other Rules Street")
    other_asset = MediaAsset.new(organization: other_organization, listing: other_listing, kind: :final, status: :ready,
                                 storage_key: "other-rules/private.jpg", filename: "private.jpg", content_type: "image/jpeg")
    other_asset.save!(validate: false)
    reference = message.message_media_references.build(media_asset: other_asset, position: 0)

    expect(reference).not_to be_valid
    expect(reference.errors.full_messages).to include("message and media asset must belong to the same organization")
  end
end

require "rails_helper"

RSpec.describe "workflow integrity models" do
  let!(:organization) { Organization.create!(name: "Integrity Agency", slug: "integrity-agency") }
  let!(:other_organization) { Organization.create!(name: "Other Integrity Agency", slug: "other-integrity-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Integrity Manager", email: "integrity-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Integrity Client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "1 Integrity Street") }
  let!(:service) do
    organization.products.create!(slug: "integrity-service", title: "Integrity service", kind: :service,
                                  deliverable_type: "photography")
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 1_000) }
  let!(:order) { Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later) }
  let!(:order_item) do
    order.order_items.create!(product: service, product_variant: variant, title: service.title, quantity: 1,
                              unit_price_cents: 1_000, total_cents: 1_000)
  end
  let!(:deliverable) do
    order.order_deliverables.create!(organization:, listing:, order_item:, service_product: service,
                                     title: service.title, deliverable_type: service.deliverable_type, sla_days: 0,
                                     materialization_key: "integrity-#{SecureRandom.uuid}")
  end
  let!(:workflow) do
    organization.default_board.board_workflows.create!(organization:, name: "Integrity workflow",
                                                        trigger_key: "order_approved", created_by: manager,
                                                        enabled: false)
  end

  it "rejects a deliverable whose listing is not the order listing" do
    another_listing = Listing.create!(organization:, client_account:, address_line_1: "2 Integrity Street")
    invalid = deliverable.dup
    invalid.materialization_key = "mismatched-listing-#{SecureRandom.uuid}"
    invalid.listing = another_listing

    expect(invalid).not_to be_valid
    expect(invalid.errors.full_messages).to include("Listing must match the order listing")
  end

  it "rejects a workflow run whose order is from another organization" do
    foreign_client = ClientAccount.create!(organization: other_organization, name: "Foreign client", kind: :agent)
    foreign_order = Order.new(organization: other_organization, client_account: foreign_client)
    invalid = workflow.runs.build(organization:, order: foreign_order,
                                  idempotency_key: "foreign-run-#{SecureRandom.uuid}", triggered_at: Time.current)

    expect(invalid).not_to be_valid
    expect(invalid.errors.full_messages).to include("Order must belong to the same organization")
  end

  it "rejects a workflow run whose definition is from another organization" do
    foreign_workflow = other_organization.default_board.board_workflows.create!(
      organization: other_organization, name: "Foreign workflow", trigger_key: "order_approved", enabled: false
    )
    invalid = BoardWorkflowRun.new(organization:, board_workflow: foreign_workflow, order:,
                                   idempotency_key: "foreign-workflow-run-#{SecureRandom.uuid}",
                                   triggered_at: Time.current)

    expect(invalid).not_to be_valid
    expect(invalid.errors.full_messages).to include("Board workflow must belong to the same organization")
  end

  it "does not allow a run step to mix actions from another workflow" do
    action = workflow.actions.create!(action_type: "link_deliverable", position: 0)
    other_workflow = organization.default_board.board_workflows.create!(organization:, name: "Other workflow",
                                                                          trigger_key: "order_approved", enabled: false)
    foreign_action = other_workflow.actions.create!(action_type: "link_deliverable", position: 0)
    run = workflow.runs.create!(organization:, order:, idempotency_key: "step-run-#{SecureRandom.uuid}",
                                triggered_at: Time.current)
    invalid = run.steps.build(board_workflow_action: foreign_action, position: 0)

    expect(invalid).not_to be_valid
    expect(invalid.errors.full_messages).to include("Board workflow action must belong to the run workflow")
    expect { run.steps.create!(board_workflow_action: action, position: 0) }.not_to raise_error
  end

  it "requires workflow status mappings to use known source states and board columns" do
    invalid_source = workflow.status_mappings.build(source_status: "queued", target_column_key: "todo", position: 0)
    invalid_column = workflow.status_mappings.build(source_status: "delivered", target_column_key: "missing", position: 1)

    expect(invalid_source).not_to be_valid
    expect(invalid_source.errors.full_messages).to include("Source status is not included in the list")
    expect(invalid_column).not_to be_valid
    expect(invalid_column.errors.full_messages).to include("Target column key must match a column on the workflow board")
  end

  it "does not allow a context-specific message reference to point at another deliverable" do
    conversation = Conversation.create!(organization:, kind: :internal, subject: "Context")
    conversation.conversation_memberships.create!(user: manager)
    message = conversation.messages.create!(author: manager, body: "Context")
    other_deliverable = order.order_deliverables.create!(organization:, listing:, order_item:, service_product: service,
                                                          title: "Other", deliverable_type: service.deliverable_type,
                                                          sla_days: 0, materialization_key: "other-#{SecureRandom.uuid}")
    asset = other_deliverable.media_assets.create!(organization:, listing:, kind: :final, status: :ready,
                                                   source_url: "https://cdn.example.test/other.jpg", filename: "other.jpg",
                                                   content_type: "image/jpeg")
    message.update!(order_deliverable: deliverable, listing: listing)

    reference = message.message_media_references.build(media_asset: asset)

    expect(reference).not_to be_valid
    expect(reference.errors.full_messages).to include("Media asset must belong to the message deliverable")
  end
end

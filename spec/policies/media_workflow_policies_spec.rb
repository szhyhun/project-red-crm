require "rails_helper"

RSpec.describe "media workflow policy contracts" do
  let!(:organization) { Organization.create!(name: "Policy contract agency", slug: "policy-contract-agency") }
  let!(:other_organization) { Organization.create!(name: "Other policy contract agency", slug: "other-policy-contract-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Policy manager", email: "policy-contract-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:staff) do
    User.create!(organization:, name: "Policy staff", email: "policy-contract-staff@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Policy contract client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Policy client", email: "policy-contract-client@example.test",
                password: "long-enough-password", role: :client_member).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :member)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "Policy Contract Street") }
  let!(:service) do
    organization.products.create!(slug: "policy-contract-service", title: "Policy contract photography",
                                  kind: :service, deliverable_type: "photography")
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
                                     materialization_key: "policy-contract-#{SecureRandom.uuid}")
  end
  let!(:workflow) do
    organization.default_board.board_workflows.create!(organization:, name: "Policy contract workflow",
                                                        trigger_key: "order_approved", enabled: false)
  end
  let!(:run) do
    workflow.runs.create!(organization:, order:, idempotency_key: "policy-run-#{SecureRandom.uuid}",
                          triggered_at: Time.current)
  end

  it "gives managers workflow configuration and run access while keeping staff out" do
    expect(BoardWorkflowPolicy.new(manager, workflow).manage?).to be(true)
    expect(BoardWorkflowPolicy.new(staff, workflow).manage?).to be(false)
    expect(BoardWorkflowRunPolicy.new(manager, run).view?).to be(true)
    expect(BoardWorkflowRunPolicy.new(staff, run).view?).to be(false)
  end

  it "lets the owning customer view a deliverable but not change production state" do
    customer_policy = OrderDeliverablePolicy.new(client_user, deliverable)

    expect(customer_policy.view?).to be(true)
    expect(customer_policy.update?).to be(false)
    expect(OrderDeliverablePolicy.new(manager, deliverable).update?).to be(true)
  end

  it "keeps deliverable and workflow access tenant-scoped" do
    foreign_client = ClientAccount.create!(organization: other_organization, name: "Foreign policy client", kind: :agent)
    foreign_listing = Listing.create!(organization: other_organization, client_account: foreign_client,
                                      address_line_1: "Foreign Policy Street")
    foreign_service = other_organization.products.create!(slug: "foreign-policy-service", title: "Foreign service",
                                                           kind: :service, deliverable_type: "video")
    foreign_variant = foreign_service.product_variants.create!(title: "Standard", price_cents: 10_000)
    foreign_order = Order.create!(organization: other_organization, client_account: foreign_client,
                                  listing: foreign_listing, payment_mode: :pay_later)
    foreign_item = foreign_order.order_items.create!(product: foreign_service, product_variant: foreign_variant,
                                                     title: foreign_service.title, quantity: 1,
                                                     unit_price_cents: 10_000, total_cents: 10_000)
    foreign_deliverable = foreign_order.order_deliverables.create!(
      organization: other_organization, listing: foreign_listing, order_item: foreign_item,
      service_product: foreign_service, title: foreign_service.title, deliverable_type: "video",
      materialization_key: "foreign-policy-deliverable-#{SecureRandom.uuid}"
    )

    expect(OrderDeliverablePolicy.new(manager, foreign_deliverable).view?).to be(false)
    expect(OrderDeliverablePolicy.new(client_user, foreign_deliverable).view?).to be(false)
  end
end

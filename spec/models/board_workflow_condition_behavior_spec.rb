require "rails_helper"

RSpec.describe BoardWorkflowCondition, type: :model do
  let!(:organization) { Organization.create!(name: "Condition behavior agency", slug: "condition-behavior-agency") }
  let!(:board) { organization.default_board }
  let!(:workflow) do
    board.board_workflows.create!(organization:, name: "Condition behavior workflow", trigger_key: "order_approved", enabled: false)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Condition client", kind: :agent) }
  let!(:service) do
    organization.products.create!(slug: "condition-photography", title: "Condition photography", kind: :service,
                                  deliverable_type: "photography")
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 10_000) }
  let!(:order) { Order.create!(organization:, client_account:, payment_mode: :pay_later) }
  let!(:deliverable) do
    item = order.order_items.create!(product: service, product_variant: variant, title: service.title, quantity: 1,
                                     unit_price_cents: 10_000, total_cents: 10_000)
    order.order_deliverables.create!(organization:, order_item: item, service_product: service,
                                     title: service.title, deliverable_type: "photography", sla_days: 0,
                                     materialization_key: "condition-behavior-#{SecureRandom.uuid}")
  end

  def build_condition(field:, operator:, value:)
    workflow.conditions.build(field:, operator:, value:, position: 0)
  end

  it "matches a scalar deliverable type exactly" do
    expect(build_condition(field: "deliverable_type", operator: "equals", value: "photography").matches?(deliverable)).to be(true)
    expect(build_condition(field: "deliverable_type", operator: "equals", value: "video").matches?(deliverable)).to be(false)
  end

  it "supports a not-equals condition without treating nil as a wildcard" do
    expect(build_condition(field: "service_product_id", operator: "not_equals", value: service.id).matches?(deliverable)).to be(false)
    expect(build_condition(field: "package_product_id", operator: "not_equals", value: service.id).matches?(deliverable)).to be(true)
  end

  it "matches values stored as either an array or a value wrapper" do
    array_condition = build_condition(field: "deliverable_type", operator: "in", value: %w[photography video])
    wrapped_condition = build_condition(field: "deliverable_type", operator: "in", value: { "value" => %w[photography video] })

    expect(array_condition.matches?(deliverable)).to be(true)
    expect(wrapped_condition.matches?(deliverable)).to be(true)
  end

  it "requires every workflow condition to match" do
    workflow.conditions.create!(field: "deliverable_type", operator: "equals", value: "photography", position: 0)
    workflow.conditions.create!(field: "service_product_id", operator: "equals", value: service.id, position: 1)

    expect(workflow.conditions_match?(deliverable)).to be(true)

    workflow.conditions.last.update!(value: "999999")
    expect(workflow.conditions_match?(deliverable)).to be(false)
  end
end

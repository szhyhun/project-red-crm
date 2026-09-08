require "rails_helper"

RSpec.describe "media workflow schema contract" do
  def columns(table)
    ActiveRecord::Base.connection.columns(table).map(&:name)
  end

  it "keeps product scope and delivery metadata relational" do
    expect(columns(:products)).to include("deliverable_type", "sla_days")
    expect(columns(:products)).not_to include("sqft")
    expect(columns(:product_variants)).to include("sqft_min", "sqft_max", "price_cents", "quantity_label")
    expect(columns(:product_variants)).not_to include("pricing", "price_tiers")
  end

  it "stores package components as first-class organization-scoped rows" do
    expect(columns(:product_components)).to include(
      "organization_id", "package_product_id", "service_product_id", "quantity", "position"
    )
  end

  it "stores approval time without changing the order line model" do
    expect(columns(:orders)).to include("approved_at")
    expect(columns(:order_items)).to include("snapshot")
  end

  it "stores deliverable lineage, immutable scope, and lifecycle state" do
    expect(columns(:order_deliverables)).to include(
      "organization_id", "listing_id", "order_id", "order_item_id", "product_component_id", "service_product_id",
      "title", "description", "deliverable_type", "sla_days", "scope_sqft_min", "scope_sqft_max", "scope_label",
      "status", "target_on", "delivered_at", "delivery_version", "position", "cancelled_at", "metadata",
      "materialization_key"
    )
  end

  it "keeps workflow definitions separate from their conditions, actions, and runs" do
    expect(columns(:board_workflows)).to include(
      "organization_id", "board_id", "name", "description", "enabled", "trigger_key", "is_default",
      "workflow_version", "created_by_id"
    )
    expect(columns(:board_workflow_conditions)).to include("board_workflow_id", "field", "operator", "value", "position")
    expect(columns(:board_workflow_actions)).to include("board_workflow_id", "action_type", "configuration", "position")
    expect(columns(:board_workflow_status_mappings)).to include("board_workflow_id", "source_status", "target_column_key")
    expect(columns(:board_workflow_runs)).to include("board_workflow_id", "order_id", "idempotency_key", "status", "retry_count")
    expect(columns(:board_workflow_run_steps)).to include("board_workflow_run_id", "board_workflow_action_id", "status", "input", "output")
  end

  it "stores shared task placements and deliverable links independently of the home task" do
    expect(columns(:workflow_task_placements)).to include(
      "workflow_task_id", "board_id", "workflow_column_id", "position", "is_home"
    )
    expect(columns(:workflow_task_deliverables)).to include("workflow_task_id", "order_deliverable_id", "position")
    expect(columns(:workflow_tasks)).to include("parent_task_id", "task_kind", "workflow_group_key")
  end

  it "keeps media versions on the existing asset table" do
    expect(columns(:media_assets)).to include("order_deliverable_id", "version", "superseded_by_id")
  end

  it "stores message context and selected asset references without copying assets" do
    expect(columns(:messages)).to include("listing_id", "order_deliverable_id", "message_kind")
    expect(columns(:message_media_references)).to include("message_id", "media_asset_id", "position")
  end
end

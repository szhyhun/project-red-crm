require "rails_helper"

RSpec.describe WorkflowTasks::Mover do
  let!(:organization) { Organization.create!(name: "Grouped mover agency", slug: "grouped-mover-agency") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Grouped mover client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "18 Grouped Mover Street") }
  let!(:photo_service) do
    organization.products.create!(slug: "grouped-mover-photo", title: "Property photography", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:video_service) do
    organization.products.create!(slug: "grouped-mover-video", title: "Property video", kind: :service,
                                  deliverable_type: "video", sla_days: 3)
  end
  let!(:order) do
    Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later,
                  status: :approved, approved_at: Time.current).tap do |record|
      photo_variant = photo_service.product_variants.create!(title: "Standard", price_cents: 20_000)
      video_variant = video_service.product_variants.create!(title: "Standard", price_cents: 30_000)
      record.order_items.create!(product: photo_service, product_variant: photo_variant,
                                 title: photo_service.title, quantity: 1, unit_price_cents: 20_000,
                                 total_cents: 20_000)
      record.order_items.create!(product: video_service, product_variant: video_variant,
                                 title: video_service.title, quantity: 1, unit_price_cents: 30_000,
                                 total_cents: 30_000)
    end
  end
  let!(:deliverables) { Orders::DeliverableMaterializer.new(order:).call }
  let!(:board) { organization.default_board }
  let!(:task) do
    board.workflow_tasks.create!(organization:, listing:, title: "Produce the media package", status: "todo").tap do |record|
      deliverables.each_with_index do |deliverable, position|
        record.workflow_task_deliverables.create!(order_deliverable: deliverable, position:)
      end
    end
  end

  it "moves every deliverable linked to a grouped task to delivered" do
    expect {
      described_class.new(task:, attributes: { status: "done", position: 0 }).move!
    }.to change { deliverables.map { |deliverable| deliverable.reload.status } }
      .from(%w[not_started not_started]).to(%w[delivered delivered])

    expect(task.reload).to have_attributes(status: "done", completed_at: be_present)
    expect(deliverables.map { |deliverable| deliverable.reload.delivered_at }).to all(be_present)
    expect(deliverables).to all(satisfy { |deliverable|
      deliverable.activity_events.where(event_type: "order_deliverable.status_changed").one?
    })
  end

  it "reopens every linked deliverable when grouped work returns to production" do
    task.update!(status: "done", completed_at: 1.hour.ago)
    deliverables.each { |deliverable| deliverable.update!(status: :delivered, delivered_at: 1.hour.ago) }

    described_class.new(task:, attributes: { status: "in_progress", position: 0 }).move!

    expect(task.reload).to have_attributes(status: "in_progress", completed_at: nil)
    expect(deliverables.map { |deliverable| deliverable.reload.status }).to all(eq("in_progress"))
    expect(deliverables.map { |deliverable| deliverable.reload.delivered_at }).to all(be_nil)
  end

  it "does not partially move a grouped task when its target column is invalid" do
    expect {
      described_class.new(task:, attributes: { status: "missing_column", position: 0 }).move!
    }.to raise_error(ActiveRecord::RecordInvalid, /must match a column on this board/)

    expect(task.reload).to have_attributes(status: "todo", completed_at: nil)
    expect(deliverables.map { |deliverable| deliverable.reload.status }).to all(eq("not_started"))
    expect(ActivityEvent.where(subject: deliverables, event_type: "order_deliverable.status_changed")).to be_empty
  end
end

class Api::V1::OrderDeliverablesController < Api::V1::BaseController
  def index
    order = policy_scope(Order).find(params[:order_id])
    authorize order, :view?
    deliverables = policy_scope(OrderDeliverable).where(order_id: order.id)
      .includes(:service_product, :media_assets, workflow_tasks: :workflow_task_placements).ordered
    render json: { order_deliverables: deliverables.map { |deliverable| serialize(deliverable) } }
  end

  def show
    deliverable = policy_scope(OrderDeliverable)
      .includes(:service_product, :media_assets, workflow_tasks: :workflow_task_placements).find(params[:id])
    authorize deliverable, :view?
    render json: { order_deliverable: serialize(deliverable, detailed: true) }
  end

  def update
    deliverable = policy_scope(OrderDeliverable).find(params[:id])
    authorize deliverable, :update?
    attributes = deliverable_params
    if attributes[:status].present?
      attributes[:delivered_at] = attributes[:status] == "delivered" ? (deliverable.delivered_at || Time.current) : nil
    end
    if deliverable.update(attributes)
      ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: deliverable,
                            event_type: "order_deliverable.updated", payload: deliverable.previous_changes)
      render json: { order_deliverable: serialize(deliverable.reload, detailed: true) }
    else
      render_validation_errors(deliverable)
    end
  end

  private

  def deliverable_params
    params.require(:order_deliverable).permit(:status, :target_on, :title, :description, :position, metadata: {})
  end

  def serialize(deliverable, detailed: false)
    customer_data = deliverable.slice(
      :id, :title, :description, :deliverable_type, :status, :target_on, :delivered_at, :scope_label
    ).merge(asset_count: deliverable.customer_visible_assets.count)
    return customer_data.merge(
      assets: deliverable.customer_visible_assets.map { |asset| serialize_asset(asset) }
    ) if detailed && !current_user.internal?
    return customer_data unless current_user.internal?

    staff_data = deliverable.slice(:id, :listing_id, :order_id, :order_item_id, :product_component_id,
                                   :service_product_id, :title, :description, :deliverable_type, :sla_days,
                                   :scope_sqft_min, :scope_sqft_max, :scope_label, :status, :target_on,
                                   :delivered_at, :delivery_version, :position, :cancelled_at, :metadata).merge(
      asset_count: deliverable.customer_visible_assets.count,
      service_product: deliverable.service_product.slice(:id, :title, :deliverable_type, :sla_days),
      workflow_tasks: deliverable.workflow_tasks.map { |task| serialize_workflow_task(task) }
    )
    return staff_data unless detailed

    staff_data.merge(
      materialization_key: deliverable.materialization_key,
      assets: deliverable.media_assets.order(:position, :created_at, :id).map { |asset| serialize_asset(asset) },
      workflow_tasks: deliverable.workflow_tasks.map { |task| { id: task.id, title: task.title, status: task.status } }
    )
  end

  def serialize_asset(asset)
    asset.slice(:id, :filename, :content_type, :byte_size, :width, :height, :duration_seconds,
                :status, :customer_visible, :position, :version, :created_at).merge(
      preview_path: asset.ready? ? "/api/v1/media_assets/#{asset.id}/preview" : nil,
      download_path: asset.ready? ? "/api/v1/media_assets/#{asset.id}/download" : nil
    )
  end

  def serialize_workflow_task(task)
    task.slice(:id, :title, :status).merge(
      board_ids: task.workflow_task_placements.order(:board_id).pluck(:board_id)
    )
  end
end

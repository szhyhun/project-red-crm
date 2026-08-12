class Api::V1::PayrollItemsController < Api::V1::BaseController
  def create
    listing = policy_scope(Listing).find(params[:listing_id])
    authorize listing, :update?
    payroll_item = listing.payroll_items.build(payroll_item_params.merge(organization: Current.organization, created_by: current_user))

    if payroll_item.save
      record_activity(listing, "payroll_item.created", payroll_item)
      render json: { payroll_item: serialize(payroll_item) }, status: :created
    else
      render_validation_errors(payroll_item)
    end
  end

  def update
    payroll_item = PayrollItem.joins(:listing).merge(policy_scope(Listing)).find(params[:id])
    authorize payroll_item.listing, :update?

    if payroll_item.update(payroll_item_params)
      record_activity(payroll_item.listing, "payroll_item.updated", payroll_item)
      render json: { payroll_item: serialize(payroll_item) }
    else
      render_validation_errors(payroll_item)
    end
  end

  def destroy
    payroll_item = PayrollItem.joins(:listing).merge(policy_scope(Listing)).find(params[:id])
    authorize payroll_item.listing, :update?
    payroll_item.update!(status: :cancelled)
    record_activity(payroll_item.listing, "payroll_item.cancelled", payroll_item)
    head :no_content
  end

  private

  def payroll_item_params
    params.require(:payroll_item).permit(:order_id, :order_item_id, :team_member_id, :title, :notes, :amount_cents, :submitted_at, :status)
  end

  def serialize(item)
    item.slice(:id, :listing_id, :order_id, :order_item_id, :title, :notes, :amount_cents, :submitted_at, :paid_at, :status, :created_at).merge(
      team_member: item.team_member && item.team_member.slice(:id, :name, :role)
    )
  end

  def record_activity(listing, event_type, item)
    ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: listing,
                          event_type:, payload: { payroll_item_id: item.id, title: item.title })
  end
end

class Api::V1::AppointmentItemsController < Api::V1::BaseController
  before_action :set_appointment

  def create
    item = @appointment.appointment_items.build(item_params)
    persist(item, :created)
  end

  def update
    persist(@appointment.appointment_items.find(params[:id]))
  end

  def destroy
    @appointment.appointment_items.find(params[:id]).destroy!
    head :no_content
  end

  private

  def set_appointment
    @appointment = Current.organization.appointments.find(params[:appointment_id])
    authorize @appointment.listing, :update?
  end

  def item_params
    params.require(:appointment_item).permit(:order_item_id, :title, :quantity)
  end

  def persist(item, status = :ok)
    if item.update(item_params)
      render json: { appointment_item: item.slice(:id, :order_item_id, :title, :quantity) }, status: status
    else
      render_validation_errors(item)
    end
  end
end

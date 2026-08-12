class AppointmentItem < ApplicationRecord
  belongs_to :appointment
  belongs_to :order_item, optional: true

  validates :title, presence: true
  validates :quantity, numericality: { greater_than: 0 }
  validate :order_item_matches_appointment_order

  private

  def order_item_matches_appointment_order
    return if order_item.blank? || appointment.blank? || appointment.order_id == order_item.order_id

    errors.add(:order_item, "must belong to the appointment order")
  end
end

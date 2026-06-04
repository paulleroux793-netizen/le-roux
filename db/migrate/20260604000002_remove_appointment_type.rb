# Diary block colour is driven by STATUS (booked→white, confirmed→green,
# arrived→yellow, in-consultation→blue, completed→purple), per the practice's
# real workflow — NOT by a separate "type". So the appointment_type column added
# earlier today is removed as vestigial.
class RemoveAppointmentType < ActiveRecord::Migration[8.1]
  def change
    remove_column :appointments, :appointment_type, :integer, null: false, default: 0
  end
end

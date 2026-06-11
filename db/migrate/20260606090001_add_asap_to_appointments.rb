class AddAsapToAppointments < ActiveRecord::Migration[8.1]
  # ASAP / "wants an earlier slot" flag — when a slot opens (cancellation), reception
  # offers it to flagged patients. The single biggest lever to cut empty chairs.
  def change
    add_column :appointments, :asap, :boolean, default: false, null: false
    add_index :appointments, :asap, where: "asap = true", name: "index_appointments_asap_true"
  end
end

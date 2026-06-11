class AddStatusMilestonesToAppointments < ActiveRecord::Migration[8.1]
  # Additive + nullable — safe to run live with zero downtime. Milestone times
  # for the front-desk status journey: waiting-room wait time (seated-arrived),
  # chair utilisation (completed-seated), and recall anchoring (completed_at).
  def change
    add_column :appointments, :arrived_at, :datetime
    add_column :appointments, :seated_at, :datetime
    add_column :appointments, :completed_at, :datetime
  end
end

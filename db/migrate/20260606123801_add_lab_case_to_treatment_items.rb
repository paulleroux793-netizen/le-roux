class AddLabCaseToTreatmentItems < ActiveRecord::Migration[8.1]
  # Lab-case tracking (crowns/bridges/dentures/aligners sent to a dental lab).
  # A treatment item becomes a "lab case" when lab_due_on is set; reception sees
  # cases due/overdue so they book the seat/fit appointment when it comes back.
  def change
    add_column :treatment_items, :lab_name,        :string
    add_column :treatment_items, :lab_sent_on,     :date
    add_column :treatment_items, :lab_due_on,      :date
    add_column :treatment_items, :lab_returned_on, :date
    add_index  :treatment_items, :lab_due_on, where: "lab_due_on IS NOT NULL AND lab_returned_on IS NULL",
                                              name: "index_treatment_items_lab_outstanding"
  end
end

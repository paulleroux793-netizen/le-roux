# Phase 5 (P5.1/5.2) — SIDEXIS imaging bridge + recalls. ADDITIVE ONLY.
# Imaging originals stay on-prem (POPIA); we store metadata + match status + a reference.
class CreateImagingAndRecalls < ActiveRecord::Migration[8.1]
  def change
    create_table :imaging_studies do |t|
      t.bigint  :patient_id                       # nullable until matched (unmatched -> needs_match queue)
      t.string  :modality, null: false, default: "other"  # intraoral_2d / panoramic / cephalometric / cbct_3d / photo / other
      t.datetime :captured_at
      t.string  :sidexis_patient_name             # the folder name from the export (for matching/review)
      t.string  :source_folder
      t.string  :source_file
      t.string  :storage_key                      # on-prem reference / thumbnail key (backend parked #18)
      t.string  :status, null: false, default: "needs_match"  # needs_match / matched / ignored
      t.text     :notes
      t.timestamps
      t.index :patient_id
      t.index :status
      t.index :modality
      t.index [ :source_folder, :source_file ], unique: true, name: "idx_imaging_unique_source"
    end

    # Preventive recalls (e.g. 6-month check-up). Outbound/additive only.
    create_table :recalls do |t|
      t.bigint  :patient_id, null: false
      t.string  :recall_type, null: false, default: "checkup"  # checkup / hygiene / followup
      t.date    :due_on, null: false
      t.string  :status, null: false, default: "due"           # due / contacted / booked / done / cancelled
      t.datetime :last_contacted_at
      t.text     :notes
      t.timestamps
      t.index [ :patient_id, :due_on ]
      t.index :status
    end

    add_foreign_key :imaging_studies, :patients
    add_foreign_key :recalls, :patients
  end
end

# Phase 1 of the Elixir mirror — keep Elixir's reality SEPARATE from Ivory's
# own data so we never accidentally pollute the schema during parser iteration.
#
# Three snapshot tables, one per Elixir source file type. Each row holds the
# raw parsed payload as JSON, plus the source-file metadata for traceability.
# The comparison view JOINs these against Ivory's own appointments / invoices
# / estimates BY DATE + PATIENT NAME / ACCOUNT (loose join — Elixir's account
# numbers may not match Ivory's patient IDs until we run a reconciliation pass).
#
# Once we're confident the parsers are accurate (after a few weeks of running),
# a SECOND migration will promote selected mirror rows into Ivory's own tables
# with proper foreign keys. For now: mirror data lives alongside, not inside.
class AddSourceToMirrorTables < ActiveRecord::Migration[8.1]
  def change
    create_table :elixir_diary_snapshots do |t|
      t.date     :diary_date, null: false
      t.string   :dentist                                      # "DR ELISKA ROBINSON" / "DR CHALITA LE ROUX"
      t.datetime :appointment_start_at, null: false            # diary_date + start_time
      t.datetime :appointment_end_at,   null: false
      t.string   :patient_name                                 # "NONDUMISO MBANJWA" (free-text, no FK)
      t.string   :account_code                                 # "M0269" or nil for new patients
      t.boolean  :is_new_patient, default: false, null: false
      t.string   :reason                                       # "FILLINGS" / "?FILLING" / "CHECK UP CLEAN"
      t.decimal  :due_amount, precision: 10, scale: 2          # 0.00 = paid up, > 0 = owing
      t.string   :cellular                                     # "0836658817"
      t.string   :source_file, null: false                     # "8 MAY 2026.pdf"
      t.datetime :imported_at, null: false
      t.jsonb    :raw_payload, default: {}, null: false        # original parsed hash for debugging
      t.timestamps
      t.index [ :diary_date, :dentist ]
      t.index [ :account_code ]
      t.index [ :patient_name ]
      t.index :imported_at
      t.index [ :source_file, :appointment_start_at ], unique: true, name: "idx_diary_snap_unique_per_slot"
    end

    create_table :elixir_transaction_snapshots do |t|
      t.date     :transaction_date, null: false
      t.string   :dentist                                      # PROVIDER row, "DR ELISKA ROBINSON" etc.
      t.string   :patient_surname                              # "ELS,M MRS"  (the format Elixir uses)
      t.string   :dependant_name                               # "MICHELLE: 10/02/1981"  or nil
      t.string   :account_code, null: false                    # "E0011"
      t.string   :procedure_code, null: false                  # "8369", "P-CARD", "B01", "C26"
      t.string   :tooth                                        # "17" / "16" / nil
      t.integer  :units, default: 1, null: false
      t.decimal  :pat_due,  precision: 10, scale: 2, default: 0
      t.decimal  :sch_due,  precision: 10, scale: 2, default: 0
      t.decimal  :debit,    precision: 10, scale: 2, default: 0   # positive = charge
      t.decimal  :credit,   precision: 10, scale: 2, default: 0   # positive = payment received (stored as positive even though PDF shows -)
      t.string   :source_file, null: false
      t.datetime :imported_at, null: false
      t.jsonb    :raw_payload, default: {}, null: false
      t.timestamps
      t.index [ :transaction_date, :account_code ]
      t.index [ :procedure_code ]
      t.index :imported_at
      t.index [ :source_file, :transaction_date, :account_code, :procedure_code, :tooth, :debit ],
              unique: true, name: "idx_txn_snap_unique"
    end

    create_table :elixir_estimate_snapshots do |t|
      t.string   :patient_name, null: false                    # "Michelle Els"
      t.string   :account_code                                 # "E0011"
      t.date     :date_sent
      t.text     :details                                      # free-text procedures
      t.date     :last_followup_at
      t.decimal  :value, precision: 10, scale: 2
      t.text     :update_note                                  # the long "Shaune sent a WA..." note
      t.string   :dentist
      t.string   :patient_aware                                # the I-column boolean-ish text
      t.string   :legend                                       # the J-column
      t.integer  :row_index, null: false                       # the .xlsx row this came from
      t.string   :source_file, null: false                     # "Estimates listing.xlsx"
      t.datetime :imported_at, null: false
      t.jsonb    :raw_payload, default: {}, null: false
      t.timestamps
      t.index [ :account_code ]
      t.index [ :patient_name ]
      t.index :imported_at
      t.index [ :source_file, :row_index ], unique: true, name: "idx_estimate_snap_unique_per_row"
    end

    create_table :elixir_mirror_imports do |t|
      t.string   :file_path, null: false                       # full path to the source file when imported
      t.string   :file_name, null: false                       # "8 MAY 2026.pdf"
      t.string   :file_kind, null: false                       # "diary" / "transaction_report" / "estimates_listing"
      t.string   :file_sha256                                  # so re-importing the same file is a no-op
      t.integer  :rows_parsed,    default: 0, null: false
      t.integer  :rows_inserted,  default: 0, null: false
      t.integer  :rows_skipped,   default: 0, null: false      # already-imported rows
      t.text     :error_message
      t.string   :status, null: false                          # "succeeded" / "failed" / "partial"
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.jsonb    :details, default: {}
      t.timestamps
      t.index [ :file_kind, :started_at ]
      t.index [ :file_sha256 ], where: "file_sha256 IS NOT NULL"
    end
  end
end

class AddAllowOverlapToAppointments < ActiveRecord::Migration[8.1]
  # Manual diary double-booking: reception may DELIBERATELY overlap-book (incl the same
  # dentist) by setting allow_overlap=true. Automated channels (WhatsApp / web chat) always
  # insert allow_overlap=false (default) AND run an app-level overlap check (slot_conflicts_
  # locally?, which scans ALL non-cancelled appts regardless of allow_overlap), so they can
  # never double-book — including over a manual override. The per-provider GiST exclusion
  # constraint becomes PARTIAL on allow_overlap so only non-override rows are constrained.
  def up
    add_column :appointments, :allow_overlap, :boolean, default: false, null: false
    execute "ALTER TABLE appointments DROP CONSTRAINT no_overlapping_appointments_per_provider"
    execute <<~SQL.squish
      ALTER TABLE appointments ADD CONSTRAINT no_overlapping_appointments_per_provider
      EXCLUDE USING gist (provider_id WITH =, tsrange(start_time, end_time) WITH &&)
      WHERE (status <> 3 AND allow_overlap = false)
    SQL
  end

  def down
    execute "ALTER TABLE appointments DROP CONSTRAINT no_overlapping_appointments_per_provider"
    execute <<~SQL.squish
      ALTER TABLE appointments ADD CONSTRAINT no_overlapping_appointments_per_provider
      EXCLUDE USING gist (provider_id WITH =, tsrange(start_time, end_time) WITH &&)
      WHERE (status <> 3)
    SQL
    remove_column :appointments, :allow_overlap
  end
end

class AddNoOverlapExclusionToAppointments < ActiveRecord::Migration[8.1]
  # Hard, database-level guard against double-booking. The model already has
  # an application-level `no_overlapping_appointments` validation, but that
  # check has a time-of-check-to-time-of-use race: two bookings hitting the
  # same slot within the same instant both pass the SELECT, then both INSERT.
  #
  # A Postgres GiST exclusion constraint makes overlapping ACTIVE appointments
  # structurally impossible — the second INSERT is rejected by the database
  # itself, regardless of application timing. status 3 = cancelled (see the
  # Appointment enum); cancelled rows free their slot so they're excluded from
  # the constraint, matching the model validation's `where.not(:cancelled)`.
  #
  # tsrange defaults to '[)' (inclusive start, exclusive end), so back-to-back
  # appointments (09:00-09:45 and 09:45-10:30) correctly do NOT count as
  # overlapping.
  #
  # Verified before adding: zero existing overlapping active pairs in production.
  def up
    enable_extension "btree_gist" unless extension_enabled?("btree_gist")

    execute <<~SQL.squish
      ALTER TABLE appointments
        ADD CONSTRAINT no_overlapping_active_appointments
        EXCLUDE USING gist (tsrange(start_time, end_time) WITH &&)
        WHERE (status <> 3)
    SQL
  end

  def down
    execute "ALTER TABLE appointments DROP CONSTRAINT IF EXISTS no_overlapping_active_appointments"
  end
end

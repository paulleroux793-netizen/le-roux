# Multi-provider diary (matches the Elixir two-column diary: one column per
# dentist). Adds a Provider, links appointments/schedules/closed-blocks to it,
# and — critically — makes the no-overlap rule PER-PROVIDER so two dentists can
# both be booked at the same clock time while one dentist still can't double-book.
class AddProvidersAndDiary < ActiveRecord::Migration[8.1]
  def up
    create_table :providers do |t|
      t.string  :name, null: false
      t.string  :short_name
      t.string  :color, null: false, default: "#16a34a" # column accent
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :providers, :name, unique: true

    add_reference :appointments, :provider, foreign_key: true, null: true, index: true
    # 0 treatment(green) · 1 consult(purple) · 2 new_patient(yellow) · 3 other(grey)
    add_column :appointments, :appointment_type, :integer, null: false, default: 0

    add_reference :calendar_notes, :provider, foreign_key: true, null: true, index: true

    add_reference :doctor_schedules, :provider, foreign_key: true, null: true, index: true
    remove_index :doctor_schedules, name: "index_doctor_schedules_on_day_of_week"
    add_index :doctor_schedules, [ :provider_id, :day_of_week ], unique: true,
              name: "index_doctor_schedules_on_provider_and_day"

    # Per-provider exclusion: needs btree_gist for the `=` on provider_id.
    enable_extension "btree_gist" unless extension_enabled?("btree_gist")
    execute "ALTER TABLE appointments DROP CONSTRAINT IF EXISTS no_overlapping_active_appointments"
    execute <<~SQL.squish
      ALTER TABLE appointments ADD CONSTRAINT no_overlapping_appointments_per_provider
      EXCLUDE USING gist (provider_id WITH =, tsrange(start_time, end_time) WITH &&)
      WHERE (status <> 3)
    SQL
  end

  def down
    execute "ALTER TABLE appointments DROP CONSTRAINT IF EXISTS no_overlapping_appointments_per_provider"
    execute <<~SQL.squish
      ALTER TABLE appointments ADD CONSTRAINT no_overlapping_active_appointments
      EXCLUDE USING gist (tsrange(start_time, end_time) WITH &&) WHERE (status <> 3)
    SQL
    remove_index :doctor_schedules, name: "index_doctor_schedules_on_provider_and_day"
    add_index :doctor_schedules, :day_of_week, unique: true,
              name: "index_doctor_schedules_on_day_of_week"
    remove_reference :doctor_schedules, :provider
    remove_reference :calendar_notes, :provider
    remove_column :appointments, :appointment_type
    remove_reference :appointments, :provider
    drop_table :providers
  end
end

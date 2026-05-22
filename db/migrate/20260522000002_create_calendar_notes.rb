class CreateCalendarNotes < ActiveRecord::Migration[8.1]
  # Diary reminders / notes — non-appointment items the doctor parks on the
  # calendar ("remember to call Mr X", an early-morning personal reminder).
  # Deliberately NOT tied to a patient: these are free-text reminders.
  def change
    create_table :calendar_notes do |t|
      t.datetime :starts_at, null: false
      t.datetime :ends_at,   null: false
      t.string  :note,       null: false
      t.boolean :done,       null: false, default: false
      t.timestamps
    end
    add_index :calendar_notes, :starts_at
  end
end

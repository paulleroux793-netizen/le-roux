class ClearLunchBreakFromDoctorSchedules < ActiveRecord::Migration[8.1]
  # Paul's v2 review (2026-05-06): the practice does not enforce a fixed
  # lunch break. Dr Chalita books over lunch organically when patients are
  # scheduled and takes lunch when there are none. The seed previously
  # hardcoded break_start = "12:00" / break_end = "13:00" which the booking
  # logic enforced as a non-bookable window. Clear those fields on every
  # active row.
  #
  # The columns themselves stay in place — a future practice (or a future
  # Dr Chalita decision) might reintroduce a break.
  def up
    DoctorSchedule.where.not(break_start: nil).update_all(break_start: nil, break_end: nil)
  end

  def down
    # Restore the previous default 12:00–13:00 break on weekday rows.
    # If the down direction matters (e.g. emergency rollback), this puts
    # the schedule back to its old shape.
    DoctorSchedule.where(active: true, day_of_week: 1..5)
                  .update_all(break_start: "12:00", break_end: "13:00")
  end
end

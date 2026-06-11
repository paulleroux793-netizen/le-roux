# DEEP STRESS TEST (safe — wrapped in a transaction that ALWAYS rolls back, nothing
# persists): edge-case correctness of cycle-17 build_unscheduled_treatment.
# A patient with planned treatment should appear ONLY when they have no upcoming
# (non-cancelled) appointment. Run: bin/rails runner script/stress/unscheduled_treatment_edge.rb
pid = 2985
p = Patient.find(pid)
pc = ProcedureCode.where("default_fee_cents > 0").order(:id).first

results = { setup_ok: false }
begin
  ActiveRecord::Base.transaction do
    # Baseline (rolled back): cancel any pre-existing upcoming appts so the patient
    # starts with NO upcoming appointment — otherwise demo appointments mask the test.
    p.appointments.where("start_time > ?", Time.current).where.not(status: :cancelled)
     .update_all(status: Appointment.statuses[:cancelled])
    cot = CourseOfTreatment.create!(patient: p, description: "STRESS TEST (rolled back)")
    TreatmentItem.create!(course_of_treatment: cot, procedure_code: pc, status: "planned")
    results[:setup_ok] = true

    seen = -> { PagesController.new.build_unscheduled_treatment.any? { |h| h[:patient_id] == pid } }

    results[:no_appt]       = seen.call                          # expect TRUE
    appt = Appointment.create!(patient: p, start_time: 2.days.from_now,
                               end_time: 2.days.from_now + 30 * 60, status: :scheduled, reason: "stress")
    results[:upcoming_appt] = seen.call                          # expect FALSE
    appt.update!(status: :cancelled)
    results[:cancelled_appt] = seen.call                         # expect TRUE again
    raise ActiveRecord::Rollback
  end
  ok = results[:no_appt] == true && results[:upcoming_appt] == false && results[:cancelled_appt] == true
  puts "unscheduled_edge: no-appt=#{results[:no_appt]} upcoming=#{results[:upcoming_appt]} cancelled=#{results[:cancelled_appt]} => #{ok ? 'PASS' : 'FAIL'}"
rescue => e
  puts "ERROR (setup_ok=#{results[:setup_ok]}): #{e.class}: #{e.message}"
end
puts "POST-CHECK persisted-test-COTs=#{CourseOfTreatment.where(description: 'STRESS TEST (rolled back)').count} (must be 0)"

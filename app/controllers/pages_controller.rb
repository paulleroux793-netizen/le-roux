class PagesController < ApplicationController
  def dashboard
    today = Date.current

    page_data = dev_page_cache("dashboard", today.iso8601) do
      todays_appointments = Appointment
        .includes(:patient)
        .where(start_time: today.all_day)
        .order(:start_time)
        .to_a

      upcoming_appointments = Appointment
        .includes(:patient)
        .where("start_time > ?", Time.current)
        .where.not(status: :cancelled)
        .order(:start_time)
        .limit(6)
        .to_a

      # Reminders widget — appointments today that are still `scheduled`
      # (unconfirmed). This is what the reception actually needs to chase up.
      reminders = todays_appointments.select { |appointment| appointment.status == "scheduled" }

      # Weekly appointment breakdown by status for the chart.
      # Shows Mon–Sun of the current week so reception can see the
      # distribution at a glance.
      week_start = today.beginning_of_week(:monday)
      week_end   = today.end_of_week(:monday)
      week_appointments = Appointment
        .where(start_time: week_start.beginning_of_day..week_end.end_of_day)
        .to_a

      weekly_chart = (0..6).map do |offset|
        day = week_start + offset.days
        day_apts = week_appointments.select { |a| a.start_time.to_date == day }
        {
          day: day.strftime("%a"),
          date: day.iso8601,
          scheduled: day_apts.count { |a| a.status == "scheduled" },
          confirmed: day_apts.count { |a| a.status == "confirmed" },
          completed: day_apts.count { |a| a.status == "completed" },
          cancelled: day_apts.count { |a| a.status == "cancelled" },
          total: day_apts.size
        }
      end

      # Recent patients for the patients table
      recent_patients = Patient
        .left_joins(:appointments)
        .select(
          "patients.*",
          "COUNT(appointments.id) AS appointment_count",
          "MAX(appointments.start_time) AS last_appointment_at"
        )
        .group("patients.id")
        .order("patients.created_at DESC")
        .limit(8)
        .to_a

      # Lightweight patient list for the appointment create modal on the dashboard.
      all_patients = Patient.order(:first_name, :last_name).limit(500).select(:id, :first_name, :last_name, :phone).to_a

      {
        stats: {
          todays_appointments: todays_appointments.size,
          pending_confirmations: reminders.size,
          confirmed_today: todays_appointments.count { |appointment| appointment.status == "confirmed" },
          total_patients: Patient.count,
          new_patients_month: Patient.where("created_at >= ?", today.beginning_of_month).count,
          total_appointments: Appointment.where.not(status: :cancelled).count,
          outstanding_balance: (Invoice.where(status: %w[open part_paid]).sum("total_cents - paid_cents").to_i / 100.0),
          # Estimate pipeline — the ACTIONABLE follow-up target: quotes not yet accepted from the
          # last 90 days (older/imported drafts are historical, not a live pipeline to chase).
          estimates_awaiting: Estimate.where(status: %w[draft sent]).where("created_at >= ?", 90.days.ago).count,
          estimates_pipeline: (Estimate.where(status: %w[draft sent]).where("created_at >= ?", 90.days.ago).sum(:total_cents).to_i / 100.0),
          whatsapp_messages: Conversation.by_channel("whatsapp").where("updated_at >= ?", 7.days.ago).count,
          flagged_patients: ConfirmationLog.flagged.joins(:appointment).where(appointments: { start_time: today.all_day }).count,
          completed_today: todays_appointments.count { |a| a.status == "completed" }
        },
        todays_appointments: todays_appointments.map { |a| appointment_props(a) },
        upcoming_appointments: upcoming_appointments.map { |a| appointment_props(a) },
        weekly_chart: weekly_chart,
        recent_patients: recent_patients.map { |p| patient_dashboard_props(p) },
        reminders: reminders.map { |a| appointment_props(a) },
        patients: all_patients.map { |p| { id: p.id, name: p.full_name, phone: p.phone } },
        # N4 — Real-time checkout banners. Currently in_chair (in_consultation)
        # or just-completed appointments where a scribe-drafted estimate is
        # ready to hand the patient. Reception sees these without polling
        # other screens.
        checkout_ready: build_checkout_banners(todays_appointments),
        # ASAP / "wants earlier" list — when a slot opens (cancellation), reception
        # offers it to these patients to fill the gap (cut empty chairs).
        asap_list: Appointment.where(asap: true)
                              .where("start_time > ?", Time.current)
                              .where.not(status: %i[cancelled completed no_show])
                              .includes(:patient).order(:start_time).limit(15)
                              .map { |a| { id: a.id, patient_name: a.patient.full_name,
                                           patient_phone: a.patient.display_phone,
                                           start_time: a.start_time.iso8601, reason: a.reason } },
        # Intake outstanding — patients with an appointment in the next 7 days who
        # have NOT completed their intake. Computed in 2 queries (no per-row N+1).
        intake_outstanding: intake_outstanding_list,
        # Recent no-shows to rebook — speed is the lever (78% rebook with whoever
        # responds first). Reception calls/messages them straight from here.
        no_shows_to_rebook: Appointment.where(status: :no_show)
          .where("start_time >= ?", 30.days.ago)
          .includes(:patient).order(start_time: :desc).limit(15)
          .map { |a| { patient_id: a.patient_id, patient_name: a.patient.full_name,
                       patient_phone: a.patient.display_phone, start_time: a.start_time.iso8601 } },
        # Lab cases due back — crowns/bridges out at the lab; reception books the
        # seat/fit when they return (and chases overdue ones).
        lab_cases_due: TreatmentItem.where.not(lab_due_on: nil).where(lab_returned_on: nil)
          .includes(:procedure_code, course_of_treatment: :patient).order(:lab_due_on).limit(15)
          .map { |i| pt = i.course_of_treatment&.patient
                     { item_id: i.id, patient_id: pt&.id, patient_name: pt&.full_name,
                       description: i.procedure_code&.description, tooth: i.tooth_number, lab_name: i.lab_name,
                       due_on: i.lab_due_on.iso8601, overdue: i.lab_due_on < Date.current } },
        # Accepted-but-unscheduled treatment — patients with PLANNED (not-yet-done)
        # treatment items but NO upcoming appointment = recoverable production to rebook.
        unscheduled_treatment: build_unscheduled_treatment
      }
    end

    render inertia: "Dashboard", props: page_data
  end

  # Read-only worklist: planned treatment items grouped by patient, excluding any
  # patient who already has an upcoming (non-cancelled) appointment. 2-3 queries, no N+1.
  def build_unscheduled_treatment
    rows = TreatmentItem.where(status: "planned")
      .joins(course_of_treatment: :patient)
      .group("patients.id")
      .pluck(Arel.sql("patients.id"), Arel.sql("COUNT(*)"), Arel.sql("COALESCE(SUM(treatment_items.fee_cents), 0)"))
    return [] if rows.empty?

    scheduled = Appointment.where("start_time > ?", Time.current)
      .where.not(status: :cancelled).distinct.pluck(:patient_id).to_set
    pending = rows.reject { |pid, _count, _cents| scheduled.include?(pid) }
    return [] if pending.empty?

    patients = Patient.where(id: pending.map(&:first)).index_by(&:id)
    pending.map { |pid, count, cents|
      { patient_id: pid, patient_name: patients[pid]&.full_name,
        item_count: count.to_i, value: cents.to_i / 100.0 }
    }.sort_by { |h| -h[:value] }.first(12)
  end

  private

  # Upcoming (7-day) appointments whose patient has NOT completed their intake.
  # Two queries total (appointments + one form_submissions sweep) — no per-row N+1.
  def intake_outstanding_list
    upcoming = Appointment.where(start_time: Time.current..7.days.from_now)
                          .where.not(status: %i[cancelled completed no_show])
                          .includes(:patient).order(:start_time).to_a
    pids = upcoming.map(&:patient_id).uniq
    return [] if pids.empty?

    subs           = FormSubmission.where(patient_id: pids).pluck(:patient_id, :status, :created_at)
    completed_pids = subs.select { |_pid, st, _| st == "completed" }.map(&:first).to_set
    latest_pending = subs.select { |_pid, st, _| %w[sent opened].include?(st) }
                         .group_by(&:first)
                         .transform_values { |rows| rows.max_by { |r| r[2] }[1] }

    upcoming.reject { |a| completed_pids.include?(a.patient_id) }.first(15).map do |a|
      { patient_id: a.patient_id, patient_name: a.patient.full_name,
        start_time: a.start_time.iso8601, intake_status: latest_pending[a.patient_id] || "not sent" }
    end
  end

  def appointment_props(appointment)
    {
      id: appointment.id,
      patient_name: appointment.patient.full_name,
      patient_phone: appointment.patient.phone,
      start_time: appointment.start_time.iso8601,
      end_time: appointment.end_time.iso8601,
      status: appointment.status,
      reason: appointment.reason
    }
  end

  # N4 — Build the "estimate ready at checkout" banners. For each today
  # appointment that is in_consultation or completed AND has a scribe-
  # drafted estimate (via the patient's most recent draft estimate), we
  # surface a one-line card on the dashboard so reception can hand the
  # document to the patient without going to look for it.
  def build_checkout_banners(todays_appointments)
    candidates = todays_appointments.select { |a|
      %w[in_consultation completed].include?(a.status)
    }
    return [] if candidates.empty?

    patient_ids = candidates.map(&:patient_id).uniq
    latest_drafts = Estimate.where(patient_id: patient_ids, status: %w[draft sent])
                            .where("created_at >= ?", 12.hours.ago)
                            .order(created_at: :desc)
                            .index_by(&:patient_id)
    candidates.filter_map do |appt|
      est = latest_drafts[appt.patient_id]
      next unless est
      {
        appointment_id: appt.id,
        patient_id: appt.patient_id,
        patient_name: appt.patient.full_name,
        status: appt.status,
        estimate_id: est.id,
        estimate_number: est.estimate_number,
        estimate_total: est.total
      }
    end
  end

  def patient_dashboard_props(patient)
    {
      id: patient.id,
      name: patient.full_name,
      phone: patient.phone,
      email: patient.email,
      appointment_count: patient.respond_to?(:appointment_count) ? patient.appointment_count : 0,
      last_appointment_at: patient.respond_to?(:last_appointment_at) && patient.last_appointment_at ? patient.last_appointment_at.iso8601 : nil,
      created_at: patient.created_at.iso8601
    }
  end
end

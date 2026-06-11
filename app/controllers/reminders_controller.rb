class RemindersController < ApplicationController
  # Phase 9.6 sub-area #7 — Pre-Appointment Reminders UI.
  #
  # Dedicated reminders page for the receptionist: lists every
  # upcoming unconfirmed appointment across a configurable window
  # (today / tomorrow / next 7 days), surfaces the most recent
  # confirmation attempt for each, and lets the user fire a one-off
  # WhatsApp or voice reminder via ConfirmationService.
  #
  # The morning batch job still runs independently — this UI is for
  # ad-hoc follow-up between batches.
  WINDOW_DAYS = 7

  def index
    today = Date.current
    window_end = (today + WINDOW_DAYS.days).end_of_day

    page_data = dev_page_cache("reminders", "index", today.iso8601) do
      # ALL upcoming appointments — the receptionist sees the full
      # picture: pending, confirmed, cancelled, etc.
      all_upcoming = Appointment
        .includes(:patient, :confirmation_logs)
        .where(start_time: today.beginning_of_day..window_end)
        .order(:start_time)
        .to_a

      pending   = all_upcoming.select { |a| a.scheduled? }
      confirmed = all_upcoming.select { |a| a.confirmed? }

      {
        reminders: all_upcoming.map { |a| reminder_props(a) },
        stats: {
          total: all_upcoming.size,
          pending: pending.size,
          confirmed: confirmed.size,
          today: all_upcoming.count { |a| a.start_time.to_date == today },
          tomorrow: all_upcoming.count { |a| a.start_time.to_date == today + 1 },
          flagged: all_upcoming.count { |a| a.confirmation_logs.any?(&:flagged) }
        }
      }
    end

    render inertia: "Reminders", props: page_data
  end

  # POST /reminders/:appointment_id/send
  #
  # Manually triggers a reminder dispatch for a single appointment
  # via the chosen channel ("whatsapp" or "voice"). Wraps
  # ConfirmationService so all the existing logging + flagging
  # flows are reused.
  def send_reminder
    appointment = Appointment.find(params[:appointment_id])
    channel = params[:method].to_s.presence || "whatsapp"

    ConfirmationService.send_reminder(appointment, method: channel)
    expire_reminder_caches!

    redirect_back fallback_location: reminders_path,
      notice: "#{channel.titleize} reminder sent to #{appointment.patient.full_name}",
      status: :see_other
  rescue ConfirmationService::SendError => e
    redirect_back fallback_location: reminders_path,
      alert: "Reminder failed: #{e.message}", status: :see_other
  rescue ArgumentError => e
    redirect_back fallback_location: reminders_path,
      alert: e.message, status: :see_other
  end

  private

  def reminder_props(appointment)
    latest_log = appointment.confirmation_logs.max_by(&:created_at)

    {
      id: appointment.id,
      patient_name: appointment.patient.full_name,
      patient_phone: appointment.patient.display_phone,
      start_time: appointment.start_time.iso8601,
      end_time: appointment.end_time.iso8601,
      reason: appointment.reason,
      status: appointment.status,
      reminder_status: derive_reminder_status(appointment, latest_log),
      hours_until: ((appointment.start_time - Time.current) / 1.hour).round(1),
      last_attempt: latest_log && {
        method: latest_log.method,
        outcome: latest_log.outcome,
        attempts: latest_log.attempts,
        flagged: latest_log.flagged,
        created_at: latest_log.created_at.iso8601
      }
    }
  end

  # Derives a human-readable reminder status from the appointment
  # status + latest confirmation log. Used by the frontend for
  # the status chip colour.
  #
  #   Pending   — appointment is scheduled, no reminder sent yet
  #   Sent      — reminder was dispatched, awaiting patient reply
  #   Confirmed — patient confirmed the appointment
  #   Cancelled — appointment was cancelled
  #   No Answer — reminder sent but patient didn't respond
  def derive_reminder_status(appointment, latest_log)
    return "Cancelled"  if appointment.cancelled?
    return "Confirmed"  if appointment.confirmed?
    return "Completed"  if appointment.completed?
    return "No Show"    if appointment.no_show?
    return "Rescheduled" if appointment.rescheduled?

    # Appointment is still scheduled — check confirmation log
    if latest_log.nil?
      "Pending"
    elsif latest_log.outcome == "confirmed"
      "Confirmed"
    elsif latest_log.outcome.in?(%w[no_answer voicemail])
      "No Answer"
    elsif latest_log.outcome.present?
      latest_log.outcome.titleize
    else
      "Sent"
    end
  end

  def expire_reminder_caches!
    expire_dev_page_cache("reminders/index")
    expire_dev_page_cache("dashboard")
  end
end

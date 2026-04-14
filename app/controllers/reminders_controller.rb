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
      # Upcoming unconfirmed appointments — the set of rows the
      # receptionist might want to chase up.
      reminders = Appointment
        .includes(:patient, :confirmation_logs)
        .where(status: [:scheduled])
        .where(start_time: today.beginning_of_day..window_end)
        .order(:start_time)
        .to_a

      {
        reminders: reminders.map { |a| reminder_props(a) },
        stats: {
          total_pending: reminders.size,
          today: reminders.count { |a| a.start_time.to_date == today },
          tomorrow: reminders.count { |a| a.start_time.to_date == today + 1 },
          this_week: reminders.size,
          flagged: reminders.count { |a| a.confirmation_logs.any?(&:flagged) }
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
      patient_phone: appointment.patient.phone,
      start_time: appointment.start_time.iso8601,
      end_time: appointment.end_time.iso8601,
      reason: appointment.reason,
      status: appointment.status,
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

  def expire_reminder_caches!
    expire_dev_page_cache("reminders/index")
    expire_dev_page_cache("dashboard")
  end
end

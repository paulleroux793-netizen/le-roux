class ConfirmationService
  # How long Twilio will let the phone ring before declaring no-answer
  DIAL_TIMEOUT = 30

  def initialize
    @twilio = Twilio::REST::Client.new(
      ENV.fetch("TWILIO_ACCOUNT_SID"),
      ENV.fetch("TWILIO_AUTH_TOKEN")
    )
  end

  # Phase 9.6 sub-area #7 — Public manual-send API used by the
  # Pre-Appointment Reminders UI.
  #
  # Creates a ConfirmationLog row and dispatches a single reminder
  # via the chosen channel. Separate from `run_daily_confirmations`
  # so the UI can send a one-off reminder without scheduling the
  # whole morning batch.
  #
  # Returns the created ConfirmationLog (already persisted).
  # Raises an error on dispatch failure so the controller can flash
  # a meaningful message to the receptionist.
  def self.send_reminder(appointment, method:)
    method = method.to_s
    raise ArgumentError, "unknown reminder method: #{method}" unless %w[voice whatsapp].include?(method)

    log = appointment.confirmation_logs.create!(
      method:   method,
      outcome:  nil,
      attempts: 1,
      flagged:  false
    )

    case method
    when "whatsapp"
      WhatsappTemplateService.new.send_reminder_24h(appointment.patient, appointment)
    when "voice"
      # Voice path still goes through the full service instance
      # because it needs the Twilio client.
      # place_confirmation_call is private so we reach in via `send`;
      # keeping it private preserves the existing morning-batch
      # encapsulation while still letting the class-level API reuse it.
      new.send(:place_confirmation_call, appointment) ||
        raise("Failed to place Twilio call")
    end

    log
  rescue StandardError => e
    Rails.logger.error("[ConfirmationService.send_reminder] #{appointment.id}: #{e.message}")
    # Re-raise a wrapped error so callers can surface to the UI.
    raise SendError, e.message
  end

  class SendError < StandardError; end

  # Entry point called by MorningConfirmationJob each morning.
  # First confirms after-hours bookings, then processes today's
  # unconfirmed (scheduled) appointments.
  def run_daily_confirmations
    confirm_after_hours_bookings
    appointments = todays_unconfirmed_appointments

    Rails.logger.info("[ConfirmationService] Processing #{appointments.count} appointments for #{Date.today}")

    appointments.each { |appointment| process_appointment(appointment) }
  end

  # Processes all pending_confirmation appointments (booked after hours).
  # For each one: if the slot is still free, promote to scheduled and
  # send a WhatsApp confirmation. If the slot now conflicts, cancel
  # and notify the patient.
  def confirm_after_hours_bookings
    pending = Appointment
      .pending_confirmation
      .where("start_time > ?", Time.current)
      .includes(:patient)
      .order(:start_time)

    Rails.logger.info("[ConfirmationService] Checking #{pending.count} after-hours booking(s)")

    pending.each do |appointment|
      if slot_available?(appointment)
        appointment.update!(status: :scheduled)
        send_after_hours_confirmed(appointment)
        Rails.logger.info("[ConfirmationService] After-hours booking #{appointment.id} confirmed for #{appointment.start_time}")
      else
        appointment.update!(status: :cancelled)
        send_after_hours_conflict(appointment)
        Rails.logger.info("[ConfirmationService] After-hours booking #{appointment.id} cancelled — slot conflict")
      end
    rescue StandardError => e
      Rails.logger.error("[ConfirmationService] After-hours booking #{appointment.id} failed: #{e.message}")
    end
  end

  private

  # Checks whether the appointment's time slot has a conflict with
  # any other non-cancelled, non-pending appointment.
  def slot_available?(appointment)
    !Appointment
      .where.not(status: [ :cancelled, :pending_confirmation ])
      .where.not(id: appointment.id)
      .where("start_time < ? AND end_time > ?", appointment.end_time, appointment.start_time)
      .exists?
  end

  def send_after_hours_confirmed(appointment)
    patient = appointment.patient
    day_name = appointment.start_time.strftime("%A")
    date_str = appointment.start_time.strftime("%-d %B %Y")
    time_str = appointment.start_time.strftime("%H:%M")

    body = <<~MSG.strip
      Good morning #{patient.first_name}! ☀️

      Great news — your appointment has been confirmed:

      #{day_name}
      #{date_str}
      #{time_str}

      Please arrive 15 minutes early to complete your patient file.

      📍 #{WhatsappService::PRACTICE_ADDRESS}

      Map: #{WhatsappService::PRACTICE_MAP_LINK}

      See you soon!
      Dr Chalita & team 🌸🌿
    MSG

    WhatsappTemplateService.new.send_text(patient.phone, body)
  rescue StandardError => e
    Rails.logger.warn("[ConfirmationService] After-hours confirmation WhatsApp failed: #{e.message}")
  end

  def send_after_hours_conflict(appointment)
    patient = appointment.patient
    day_name = appointment.start_time.strftime("%A")
    date_str = appointment.start_time.strftime("%-d %B %Y")
    time_str = appointment.start_time.strftime("%H:%M")

    body = <<~MSG.strip
      Good morning #{patient.first_name},

      Unfortunately, the time slot you requested (#{day_name} #{date_str} at #{time_str}) is no longer available.

      Would you like to book a different time? Just send us your preferred day and time and we'll get you sorted. 😊

      Dr Chalita & team
    MSG

    WhatsappTemplateService.new.send_text(patient.phone, body)
  rescue StandardError => e
    Rails.logger.warn("[ConfirmationService] After-hours conflict WhatsApp failed: #{e.message}")
  end

  def todays_unconfirmed_appointments
    Appointment
      .scheduled
      .where(start_time: Date.today.all_day)
      .includes(:patient)
      .order(:start_time)
  end

  # For a single appointment:
  #   1. Create a ConfirmationLog to track the attempt
  #   2. Try an outbound voice call via Twilio
  #   3. If the call fails, fall back to a WhatsApp template
  #   4. If both fail, flag for manual follow-up by reception
  #
  # Note: the actual outcome (confirmed / rescheduled / cancelled) is written
  # asynchronously by VoiceController#confirmation_gather when the patient
  # responds. The log created here is updated at that point.
  def process_appointment(appointment)
    log = appointment.confirmation_logs.create!(
      method:   "voice",
      outcome:  nil,
      attempts: 0,
      flagged:  false
    )

    if place_confirmation_call(appointment)
      log.update!(attempts: 1)
    else
      log.update!(attempts: 1)
      send_whatsapp_fallback(appointment, log)
    end
  rescue StandardError => e
    Rails.logger.error("[ConfirmationService] Appointment #{appointment.id}: #{e.message}")
    flag_for_manual_review(appointment, "System error during morning confirmation: #{e.message}")
  end

  # Places an outbound Twilio call to the patient.
  # Returns true if the call was successfully queued, false on Twilio API error.
  def place_confirmation_call(appointment)
    app_base_url      = ENV.fetch("APP_BASE_URL", "http://localhost:3000")
    confirmation_url  = "#{app_base_url}/webhooks/voice/confirmation?appointment_id=#{appointment.id}"
    status_url        = "#{app_base_url}/webhooks/voice/status"

    @twilio.calls.create(
      to:               appointment.patient.phone,
      from:             ENV.fetch("TWILIO_PHONE_NUMBER"),
      url:              confirmation_url,
      status_callback:  status_url,
      timeout:          DIAL_TIMEOUT,
      machine_detection: "Enable"
    )

    Rails.logger.info("[ConfirmationService] Call placed to #{appointment.patient.phone} for appointment #{appointment.id}")
    true
  rescue Twilio::REST::TwilioError => e
    Rails.logger.error("[ConfirmationService] Call failed for #{appointment.patient.phone}: #{e.message}")
    false
  end

  # Sends the appointment_confirmation WhatsApp template as a fallback when
  # the voice call could not be placed (e.g. bad number or Twilio error).
  def send_whatsapp_fallback(appointment, log)
    WhatsappTemplateService.new.send_confirmation(appointment.patient, appointment)
    log.update!(method: "whatsapp")
    Rails.logger.info("[ConfirmationService] WhatsApp fallback sent to #{appointment.patient.phone}")
  rescue WhatsappTemplateService::Error => e
    Rails.logger.error("[ConfirmationService] WhatsApp fallback failed: #{e.message}")
    flag_for_manual_review(appointment, "Voice call and WhatsApp both failed for confirmation")
    log.update!(flagged: true, outcome: "no_answer")
  end

  # Flags the appointment's most recent confirmation log and sends an alert
  # to reception via the flagged_patient_alert template.
  def flag_for_manual_review(appointment, reason)
    log = appointment.confirmation_logs.order(created_at: :desc).first
    log&.update!(flagged: true)

    WhatsappTemplateService.new.send_flagged_alert(appointment.patient, reason)
  rescue WhatsappTemplateService::Error => e
    Rails.logger.error("[ConfirmationService] Alert send failed for appointment #{appointment.id}: #{e.message}")
  end
end

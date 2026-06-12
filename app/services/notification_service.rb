class NotificationService
  # Phase 9.6 sub-area #6 — Notification System.
  #
  # Central place where domain events turn into Notification rows.
  # Controllers call into one of the `appointment_*` / `patient_*` /
  # `conversation_*` class methods instead of constructing
  # notifications inline, so:
  #
  #   - The copy lives in one file (easy to audit / translate later)
  #   - Notification emission is idempotent and rescue-wrapped, so a
  #     failure to log a notification never blocks the primary save
  #   - A future job queue (ActionCable / email / push) hooks in here
  #     without touching the controllers
  class << self
    def appointment_created(appointment)
      emit(
        category: "appointment_created",
        level: "info",
        title: "New appointment booked",
        body: "#{appointment.patient.full_name} — #{format_time(appointment.start_time)}",
        url: "/appointments/#{appointment.id}",
        patient: appointment.patient,
        appointment: appointment
      )
    end

    def appointment_cancelled(appointment, reason: nil)
      body = "#{appointment.patient.full_name} — #{format_time(appointment.start_time)}"
      body += " · #{reason}" if reason.present?
      emit(
        category: "appointment_cancelled",
        level: "warning",
        title: "Appointment cancelled",
        body: body,
        url: "/appointments/#{appointment.id}",
        patient: appointment.patient,
        appointment: appointment
      )
    end

    def appointment_confirmed(appointment)
      emit(
        category: "appointment_confirmed",
        level: "success",
        title: "Appointment confirmed",
        body: "#{appointment.patient.full_name} — #{format_time(appointment.start_time)}",
        url: "/appointments/#{appointment.id}",
        patient: appointment.patient,
        appointment: appointment
      )
    end

    def appointment_rescheduled(appointment)
      emit(
        category: "appointment_rescheduled",
        level: "info",
        title: "Appointment rescheduled",
        body: "#{appointment.patient.full_name} — now #{format_time(appointment.start_time)}",
        url: "/appointments/#{appointment.id}",
        patient: appointment.patient,
        appointment: appointment
      )
    end

    def patient_created(patient)
      emit(
        category: "patient_created",
        level: "success",
        title: "New patient added",
        body: "#{patient.full_name} · #{patient.phone}",
        url: "/patients/#{patient.id}",
        patient: patient
      )
    end

    def intake_completed(patient)
      emit(
        category: "intake_completed",
        level: "success",
        title: "Patient form completed",
        body: "#{patient.full_name} completed their online intake form",
        url: "/patients/#{patient.id}",
        patient: patient
      )
    end

    def conversation_started(conversation)
      emit(
        category: "conversation_started",
        level: "info",
        title: "New conversation",
        body: "#{conversation.patient.full_name} via #{conversation.channel}",
        url: "/conversations/#{conversation.id}",
        patient: conversation.patient,
        conversation: conversation
      )
    end

    private

    # Create the row, rescuing ANY error so the primary controller
    # flow is never broken by a notification logging failure.
    def emit(attrs)
      Notification.create!(**attrs)
    rescue StandardError => e
      Rails.logger.error("[NotificationService] emit failed: #{e.message}")
      nil
    end

    def format_time(time)
      return "" if time.nil?
      time.strftime("%b %-d, %H:%M")
    end
  end
end

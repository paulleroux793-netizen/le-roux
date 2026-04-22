class WhatsappTemplateService
  # Template Content SIDs from Twilio Console
  # Set these in your .env file after templates are approved
  def self.templates
    {
      confirmation: ENV.fetch("WHATSAPP_TPL_CONFIRMATION", ""),
      reminder_24h: ENV.fetch("WHATSAPP_TPL_REMINDER_24H", ""),
      reminder_1h: ENV.fetch("WHATSAPP_TPL_REMINDER_1H", ""),
      cancellation: ENV.fetch("WHATSAPP_TPL_CANCELLATION", ""),
      reschedule: ENV.fetch("WHATSAPP_TPL_RESCHEDULE", ""),
      flagged_alert: ENV.fetch("WHATSAPP_TPL_FLAGGED_ALERT", ""),
      confirm_request: ENV.fetch("WHATSAPP_TPL_CONFIRM_REQUEST", "")
    }
  end

  class Error < StandardError; end

  def initialize
    @client = Twilio::REST::Client.new(
      ENV.fetch("TWILIO_ACCOUNT_SID"),
      ENV.fetch("TWILIO_AUTH_TOKEN")
    )
    @from = "whatsapp:#{ENV.fetch('TWILIO_WHATSAPP_NUMBER')}"
  end

  # Send appointment confirmation after booking
  # Variables: {{1}} patient_name, {{2}} date, {{3}} time
  def send_confirmation(patient, appointment)
    send_template(:confirmation, patient.phone, {
      "1" => patient.first_name,
      "2" => appointment.start_time.strftime("%A, %b %d"),
      "3" => appointment.start_time.strftime("%I:%M %p")
    })
  end

  # Send 24-hour reminder
  # Variables: {{1}} patient_name, {{2}} time
  def send_reminder_24h(patient, appointment)
    send_template(:reminder_24h, patient.phone, {
      "1" => patient.first_name,
      "2" => appointment.start_time.strftime("%I:%M %p")
    })
  end

  # Send 1-hour reminder
  # Variables: {{1}} patient_name, {{2}} time
  def send_reminder_1h(patient, appointment)
    send_template(:reminder_1h, patient.phone, {
      "1" => patient.first_name,
      "2" => appointment.start_time.strftime("%I:%M %p")
    })
  end

  # Send cancellation confirmation
  # Variables: {{1}} patient_name, {{2}} date
  def send_cancellation(patient, appointment)
    send_template(:cancellation, patient.phone, {
      "1" => patient.first_name,
      "2" => appointment.start_time.strftime("%A, %b %d")
    })
  end

  # Send reschedule confirmation
  # Variables: {{1}} patient_name, {{2}} new_date, {{3}} new_time
  def send_reschedule(patient, appointment)
    send_template(:reschedule, patient.phone, {
      "1" => patient.first_name,
      "2" => appointment.start_time.strftime("%A, %b %d"),
      "3" => appointment.start_time.strftime("%I:%M %p")
    })
  end

  # Phase 10.1 — Free-form outbound WhatsApp message.
  #
  # Unlike the template helpers above, this sends a plain-text body
  # without a pre-approved Twilio Content SID. Twilio only permits
  # free-form messages inside the 24-hour customer service window
  # (i.e. the patient has messaged us within the last 24 hours); if
  # the window has expired Twilio will return a 63016-style error
  # and this method will surface it as Error so the caller can show
  # the receptionist a useful message.
  def send_text(to_phone, body)
    raise Error, "message body cannot be blank" if body.to_s.strip.empty?

    formatted_phone = format_phone(to_phone)
    @client.messages.create(
      from: @from,
      to:   "whatsapp:#{formatted_phone}",
      body: body
    )
  rescue Twilio::REST::TwilioError => e
    Rails.logger.error("[WhatsApp] Failed to send free-form text to #{to_phone}: #{e.message}")
    raise Error, "Failed to send WhatsApp message: #{e.message}"
  end

  # Send interactive confirmation request for an upcoming appointment.
  # Uses a Twilio quick-reply template (WHATSAPP_TPL_CONFIRM_REQUEST) when
  # configured — buttons payload "CONFIRM_APPOINTMENT" / "RESCHEDULE_APPOINTMENT".
  # Falls back to a formatted free-form text message if the template SID is not set.
  # Variables: {{1}} patient_name, {{2}} date, {{3}} time
  def send_confirmation_request_with_buttons(patient, appointment)
    content_sid = self.class.templates[:confirm_request]
    if content_sid.present?
      send_template(:confirm_request, patient.phone, {
        "1" => patient.first_name,
        "2" => appointment.start_time.strftime("%A, %b %d"),
        "3" => appointment.start_time.strftime("%I:%M %p")
      })
    else
      send_confirmation_request_text(patient, appointment)
    end
  end

  # Send flagged patient alert to reception
  # Variables: {{1}} patient_name, {{2}} phone, {{3}} reason
  def send_flagged_alert(patient, reason)
    reception_phone = ENV.fetch("RECEPTION_WHATSAPP_NUMBER", ENV.fetch("TWILIO_WHATSAPP_NUMBER"))
    send_template(:flagged_alert, reception_phone, {
      "1" => patient.full_name,
      "2" => patient.phone,
      "3" => reason
    })
  end

  private

  # Plain-text fallback when WHATSAPP_TPL_CONFIRM_REQUEST is not configured.
  # Instructs the patient to reply with the exact keyword the inbound handler
  # recognises ("CONFIRM APPOINTMENT" / "RESCHEDULE APPOINTMENT").
  def send_confirmation_request_text(patient, appointment)
    day_name = appointment.start_time.strftime("%A")
    date_str = appointment.start_time.strftime("%-d %B %Y")
    time_str = appointment.start_time.strftime("%H:%M")

    body = <<~MSG.strip
      Hi #{patient.first_name} 👋

      Reminder: you have an appointment *tomorrow*:

      📅 #{day_name}, #{date_str}
      🕐 #{time_str}

      Please let us know:
      ✅ Reply *CONFIRM APPOINTMENT* to confirm
      🔄 Reply *RESCHEDULE APPOINTMENT* to request a new time

      Dr Chalita & team
    MSG

    send_text(patient.phone, body)
  end

  def send_template(template_key, to_phone, variables)
    content_sid = self.class.templates[template_key]
    raise Error, "Template '#{template_key}' not configured (missing Content SID)" if content_sid.blank?

    formatted_phone = format_phone(to_phone)

    @client.messages.create(
      from: @from,
      to: "whatsapp:#{formatted_phone}",
      content_sid: content_sid,
      content_variables: variables.to_json
    )
  rescue Twilio::REST::TwilioError => e
    Rails.logger.error("[WhatsApp Template] Failed to send #{template_key}: #{e.message}")
    raise Error, "Failed to send #{template_key} template: #{e.message}"
  end

  def format_phone(phone)
    # Ensure phone has country code prefix
    phone.start_with?("+") ? phone : "+#{phone}"
  end
end

# The website chat widget's brain — the SAME one the WhatsApp bot uses. Mirrors
# WhatsappService#handle_incoming for the web channel: it reuses AiService (channel: :web)
# for the conversation + intent/entities, and the shared BookingEngine for the actual booking
# (identical guards: no weekends, no after-hours, no double-booking). No Twilio — returns JSON.
#
# POPIA: a booking is only created once the visitor has given a WhatsApp number AND consent.
# After a successful booking the controller sends the WhatsApp "pack" (directions, address,
# Maps link, intake form, appointment details) — see WebChatController/cycle 6.
class WebChatService
  def initialize(ai_service: AiService.new)
    @ai = ai_service
  end

  # One conversation turn. Returns a channel-agnostic hash for the widget.
  def handle_message(session_id:, message:, visitor_name: nil, visitor_phone: nil, consent: false)
    session = find_or_create_session(session_id)
    update_contact(session, visitor_name, visitor_phone, consent)

    result   = @ai.process_message(message: message, conversation: session, patient: session.patient, channel: :web)
    intent   = result[:intent].to_s
    entities = result[:entities] || {}
    # Public-website channel — scrub the AI's free text through the SAME compliance filter the
    # WhatsApp line uses (bans "24/7", "painless", medical-aid-direct, Pretoria, …) before it
    # ever reaches a visitor. Controlled booking replies below are already compliant.
    reply    = ComplianceFilter.scrub(result[:response].to_s)[:text]
    booked   = nil

    if booking_requested?(intent, entities)
      if ready_to_book?(session)
        outcome = BookingEngine.call(
          patient: patient_for(session), date: entities[:date], time: entities[:time], treatment: entities[:treatment]
        )
        case outcome.status
        when :booked
          booked = outcome.appointment
          session.update!(status: "booked", patient: booked.patient)
          send_whatsapp_pack(booked)
          reply = confirmation_reply(booked)
        when :already_booked
          reply = already_booked_reply(outcome.existing)
        when :too_soon, :slot_taken, :outside_working_hours, :after_hours_today, :public_holiday
          reply = recoverable_reply(outcome.status, entities[:date])
        end
      end
    end

    {
      reply:          reply,
      intent:         intent,
      entities:       entities,
      booked:         booked.present?,
      appointment_id: booked&.id,
      needs_contact:  booking_requested?(intent, entities) && !ready_to_book?(session),
      session_id:     session.session_id
    }
  end

  private

  def booking_requested?(intent, entities)
    intent == "book" && entities[:date].present? && entities[:time].present?
  end

  # POPIA gate — never book until we have a WhatsApp number + explicit consent.
  def ready_to_book?(session)
    session.visitor_phone.present? && session.consented?
  end

  def find_or_create_session(session_id)
    WebChatSession.find_or_create_by!(session_id: session_id) do |s|
      s.source = "web_chat"
      s.status = "active"
    end
  end

  def update_contact(session, name, phone, consent)
    session.visitor_name  = name if name.present?
    session.visitor_phone = phone if phone.present?
    session.whatsapp_consent_at ||= Time.current if consent
    session.save! if session.changed?
  end

  def patient_for(session)
    return session.patient if session.patient

    parts = session.visitor_name.to_s.strip.split
    patient = Patient.find_or_create_by!(phone: normalize_phone(session.visitor_phone)) do |p|
      p.first_name = parts.first.presence || "Web"
      p.last_name  = parts[1..]&.join(" ").presence || "Visitor"
      p.consent_to_ai_processing_at = Time.current
    end
    session.update!(patient: patient)
    patient
  end

  def normalize_phone(phone)
    phone.to_s.gsub(/\s+/, "").then { |p| p.start_with?("+") ? p : "+#{p}" }
  end

  # After a successful web booking, deliver the SAME WhatsApp pack reception sends —
  # location, directions, intake-form link, and the booking confirmation. Never breaks booking.
  def send_whatsapp_pack(appointment)
    WhatsappPackSender.call(appointment)
  rescue StandardError => e
    Rails.logger.error("[WebChat] pack send failed (booking stands): #{e.class}: #{e.message}")
  end

  # --- web-voice replies ---
  # On a successful web booking the patient gets (1) an approved CONFIRMATION template on
  # WhatsApp (WhatsappPackSender) and (2) the intake-form link + address shown right here in the
  # widget — the reliable channel, since a first-contact free-form WhatsApp can't be guaranteed.
  def confirmation_reply(appt)
    when_str = appt.start_time.strftime("%A %-d %B at %H:%M")
    intake   = intake_link_for(appt.patient)
    lines = [ "You're all booked for #{when_str} 🎉", "I've sent a confirmation to your WhatsApp." ]
    if intake
      lines << "Please complete your secure intake form before your visit — about 5 minutes, " \
               "paperless and private 🔐: #{intake}"
    end
    lines << "We're at Office Park, cnr Doreen & Lawrence Rd, Amorosa, Roodepoort — " \
             "#{WhatsappStandardMessages::MAP_LINK}. We look forward to seeing you! 🌸"
    lines.join("\n\n")
  end

  # Mint the patient's tokenised intake link to show in the widget (no WhatsApp send).
  # Never breaks the booking — on any failure the confirmation simply omits the link.
  def intake_link_for(patient)
    IntakeDispatch.prepare(patient)
  rescue StandardError => e
    Rails.logger.warn("[WebChat] intake link prep failed (booking stands): #{e.class}: #{e.message}")
    nil
  end

  def already_booked_reply(existing)
    if existing
      "You're already booked in for *#{existing.start_time.strftime('%A %-d %B at %H:%M')}* 😊 " \
        "Nothing more to do — would you like to change it?"
    else
      "You're already booked in with us 😊 Would you like to change anything?"
    end
  end

  def recoverable_reply(status, date)
    base = case status
           when :outside_working_hours then "That time is outside our hours — we're open Monday to Friday, 8am–5pm."
           when :public_holiday        then "We're closed that day (we're closed on weekends and public holidays)."
           when :slot_taken            then "Ah, that slot was just taken."
           when :too_soon              then "That's a little too soon for us to prepare for you."
           when :after_hours_today     then "We've closed for today, but I'd love to get you booked."
           else                             "That didn't quite work."
           end
    slots = next_slots(date)
    if slots.any?
      # AvailabilityService returns already-formatted strings ("Wednesday, 17 June at 11:00").
      listed = slots.each_with_index.map { |s, i| "#{i + 1}. #{s}" }.join("\n")
      "#{base} Here are the next available times:\n#{listed}\nWhich suits you?"
    else
      "#{base} Could you suggest another day and I'll find the closest slot?"
    end
  end

  def next_slots(date)
    from = (Date.parse(date.to_s) rescue Date.current)
    AvailabilityService.new.next_available_slots(from_date: from, limit: 3)
  rescue StandardError
    []
  end
end

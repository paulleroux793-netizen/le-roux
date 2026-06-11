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
    # Detect + persist the patient's language so BOTH the AI's own replies and our scripted booking
    # replies are bilingual. AiService also reads session.language, so setting it here flips the whole
    # turn to Afrikaans. Conservative: only switch on a clear AF signal; once set it sticks.
    detect_and_set_language(session, message)
    @lang = session.language

    result   = @ai.process_message(message: message, conversation: session, patient: session.patient, channel: :web)
    intent   = result[:intent].to_s
    entities = result[:entities] || {}
    # Public-website channel — scrub the AI's free text through the SAME compliance filter the
    # WhatsApp line uses (bans "24/7", "painless", medical-aid-direct, Pretoria, …) before it
    # ever reaches a visitor. Controlled booking replies below are already compliant.
    reply    = ComplianceFilter.scrub(result[:response].to_s)[:text]
    booked   = nil

    # Guard against the AI mis-resolving a relative date ("this Friday" -> a Tuesday).
    # The classifier returns the weekday it BELIEVES the resolved date falls on; if that
    # disagrees with the real calendar weekday, it likely picked the wrong day — hold and ask
    # the patient to confirm instead of booking the wrong day. Mirrors WhatsappService.
    wants_booking = booking_requested?(intent, entities)
    # Deterministically correct a mis-resolved relative date. LLMs are weak at date arithmetic
    # (Perplexity-researched best practice: resolve relative dates in CODE, not the model). If the
    # AI's ISO date contradicts the weekday it reported, trust the weekday (which the patient
    # actually said) and recompute the next upcoming occurrence of it. Only if we still can't
    # reconcile (no usable weekday) do we fall back to asking the patient.
    if wants_booking && (fixed = correct_mismatched_date(entities))
      entities = entities.merge(date: fixed)
    end
    date_unresolved = wants_booking && date_day_of_week_mismatch?(entities[:date], entities[:day_of_week])
    # Chair-fill: when the patient wants to book but hasn't named a day yet, LEAD with the soonest
    # available slot + a couple of near alternatives (Perplexity best practice: always lead with the
    # earliest, offer choice, confirm before booking — never silent auto-book). Keeps the diary full.
    offer_soonest = intent == "book" && entities[:date].blank? && session.status != "booked"
    # Pre-validate the requested slot against the SAME guards BookingEngine uses, BEFORE asking for
    # contact details — so a closed day (weekend / a SA public holiday the AI doesn't know / a past
    # time / after-hours) is caught immediately and we offer alternatives, instead of collecting the
    # patient's details for a day we can never book.
    pre_reject = (wants_booking && !date_unresolved) ? unbookable_reason(entities) : nil

    if offer_soonest
      reply = soonest_slots_reply(entities[:treatment])
    elsif date_unresolved
      reply = date_mismatch_reply(entities[:date], entities[:day_of_week])
    elsif pre_reject
      reply = recoverable_reply(pre_reject, entities[:date])
    elsif wants_booking && ready_to_book?(session)
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

    {
      reply:          reply,
      intent:         intent,
      entities:       entities,
      booked:         booked.present?,
      appointment_id: booked&.id,
      needs_contact:  wants_booking && !date_unresolved && pre_reject.nil? && !ready_to_book?(session),
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

  # True when the AI's self-reported weekday disagrees with the actual calendar weekday of the
  # resolved ISO date — a sign it mis-resolved a relative phrase. Copied from WhatsappService so
  # both channels behave identically. Unparseable date => false (let booking logic handle it).
  # Lead with the soonest available chair + up to 2 near alternatives, then invite a choice.
  # Uses the SAST-aware NextAvailableSlotFinder for the provider new bookings route to.
  def soonest_slots_reply(treatment)
    slots = soonest_slots(treatment, limit: 3)
    if slots.empty?
      return af? ?
        "Ek sal jou graag so gou moontlik inkry! Watter dag pas jou die beste — en verkies jy " \
        "oggende of middae? Ek sal die naaste oop tyd kry. 😊" :
        "I'd love to get you in as soon as possible! Which day suits you best — and do you " \
        "prefer mornings or afternoons? I'll find the closest open time. 😊"
    end
    lead   = slots.first
    others = slots[1..].map { |t| "• #{fmt_slot(t)}" }.join("\n")
    if af?
      msg = "Ons vroegste beskikbare tyd is *#{fmt_slot(lead)}*."
      msg += "\nAnder tye naby:\n#{others}" if slots.size > 1
      msg + "\n\nWil jy die vroegste een hê, of sê my watter dag jou pas, dan kry ek die naaste tyd. 😊"
    else
      msg = "Our soonest available is *#{fmt_slot(lead)}*."
      msg += "\nOther close times:\n#{others}" if slots.size > 1
      msg + "\n\nWould you like the soonest one, or tell me a day that suits and I'll find the closest time. 😊"
    end
  end

  def soonest_slots(treatment, limit: 3)
    provider = Provider.default_booking_provider
    return [] unless provider
    # Start from now + the SAME booking buffer BookingEngine enforces, so every slot we OFFER is
    # actually bookable (otherwise we'd suggest a time that comes back :too_soon).
    buffer = (PracticeConfig.booking_buffer_minutes.to_i rescue 30)
    from   = Time.current + buffer.minutes
    NextAvailableSlotFinder.call(provider: provider, duration_min: practice_duration(treatment),
                                 from: from, limit: limit)
                           .map { |iso| Time.zone.parse(iso) }
  rescue StandardError => e
    Rails.logger.warn("[WebChat] soonest_slots failed: #{e.class}: #{e.message}")
    []
  end

  def practice_duration(treatment)
    d = (PracticeConfig.duration_for(treatment).to_i rescue 0)
    d.positive? ? d : 30
  end

  # The guard status that would block this slot (:too_soon / :public_holiday /
  # :outside_working_hours / :slot_taken), or nil if bookable. Uses BookingEngine's OWN guards so
  # the pre-check and the real booking can never disagree. Best-effort: nil (let booking decide) on error.
  def unbookable_reason(entities)
    start = (Time.zone.parse("#{entities[:date]} #{entities[:time]}") rescue nil)
    return nil unless start
    eng    = BookingEngine.new
    finish = start + eng.duration_for_treatment(entities[:treatment])
    return :too_soon if start <= Time.current + (PracticeConfig.booking_buffer_minutes.to_i rescue 30).minutes
    return :public_holiday if eng.public_holiday?(start.to_date)
    return :outside_working_hours unless eng.slot_within_working_hours?(start, finish)
    return :slot_taken if eng.slot_conflicts_locally?(start, finish)
    nil
  rescue StandardError => e
    Rails.logger.warn("[WebChat] unbookable_reason failed: #{e.class}: #{e.message}")
    nil
  end

  WEEKDAYS = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze

  # When the AI's date and its claimed weekday disagree, recompute the date as the next upcoming
  # occurrence of that (patient-stated) weekday. Returns the corrected ISO date string, or nil if
  # there's no mismatch or the weekday isn't usable (then the mismatch guard holds + asks).
  def correct_mismatched_date(entities)
    return nil unless date_day_of_week_mismatch?(entities[:date], entities[:day_of_week])
    d = next_weekday_date(entities[:day_of_week])
    return nil unless d
    Rails.logger.info("[WebChat] corrected mis-resolved date #{entities[:date].inspect} " \
                      "(AI said #{entities[:day_of_week]}) -> #{d.iso8601}")
    d.iso8601
  end

  # Next upcoming occurrence of a named weekday (documented business rule: strictly 1..7 days
  # ahead — a relative weekday phrase like "this Friday" rarely means today).
  def next_weekday_date(day_name)
    target = WEEKDAYS.index { |d| d[0, 3].casecmp?(day_name.to_s.strip[0, 3]) }
    return nil unless target
    today = Date.current
    delta = (target - today.wday) % 7
    delta = 7 if delta.zero?
    today + delta
  end

  def date_day_of_week_mismatch?(date, claimed_day_of_week)
    return false if claimed_day_of_week.blank?

    actual_day = Date.parse(date.to_s).strftime("%A")
    claimed = claimed_day_of_week.to_s.strip
    valid_days = %w[Monday Tuesday Wednesday Thursday Friday Saturday Sunday]
    return false unless valid_days.any? { |d| d[0, 3].casecmp?(claimed[0, 3]) }

    !actual_day[0, 3].casecmp?(claimed[0, 3])
  rescue ArgumentError, TypeError
    false
  end

  # Friendly clarification when the resolved date's weekday contradicts what the patient asked
  # for — ask them to restate the day rather than booking the wrong one.
  def date_mismatch_reply(date, _claimed)
    actual = (Date.parse(date.to_s) rescue nil)
    if af?
      actual ? "Net om seker te maak ek bespreek die regte dag — #{actual.day} #{AF_MONTHS[actual.month - 1]} " \
               "is 'n #{AF_DAYS[actual.wday]}. Watter dag wil jy hê? Sê my die datum of die weekdag, dan kry ek die naaste oop tyd. 😊" :
               "Watter dag wil jy inkom? Gee my 'n datum of 'n weekdag, dan kry ek die naaste oop tyd. 😊"
    else
      actual ? "Just to be sure I book the right day — #{actual.strftime('%-d %B')} is a #{actual.strftime('%A')}. " \
               "Which day would you like? Tell me the date or the weekday and I'll find the closest available time. 😊" :
               "Which day would you like to come in? Give me a date or a weekday and I'll find the closest available time. 😊"
    end
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

  # ── Bilingual (EN/AF) support ──────────────────────────────────────────────
  AF_DAYS   = %w[Sondag Maandag Dinsdag Woensdag Donderdag Vrydag Saterdag].freeze
  AF_MONTHS = %w[Januarie Februarie Maart April Mei Junie Julie Augustus September Oktober November Desember].freeze
  # Distinctly-Afrikaans words (low English false-positive) used to detect the patient's language.
  AF_MARKERS = %w[
    ek wil graag bespreek asseblief asb vandag dankie goeiedag goeiemôre tande tandarts
    skoonmaak afspraak vrydag maandag dinsdag woensdag donderdag saterdag sondag oggend
    aand middag volgende wanneer naweek vakansiedag
  ].freeze

  def af? = @lang == "af"

  # Switch the session to Afrikaans on a clear signal (>=2 distinct AF markers); once AF it stays AF.
  # Persisted on the session, which AiService also reads so its own replies switch too.
  def detect_and_set_language(session, message)
    return if session.language == "af"
    words = message.to_s.downcase.scan(/[a-zà-ÿ']+/)
    return if words.empty?
    hits = words.uniq.count { |w| AF_MARKERS.include?(w) }
    session.update!(language: "af") if hits >= 2
  end

  # Localized slot label — "Friday 12 June at 11:00" / "Vrydag 12 Junie om 11:00".
  def fmt_slot(time)
    if af?
      "#{AF_DAYS[time.wday]} #{time.day} #{AF_MONTHS[time.month - 1]} om #{time.strftime('%H:%M')}"
    else
      time.strftime("%A %-d %B at %H:%M")
    end
  end

  # Structured upcoming open Times for the default booking provider, from `from` — so callers can
  # format them in the patient's language (holiday/buffer/conflict-aware via NextAvailableSlotFinder).
  def open_times(from:, limit: 3)
    provider = Provider.default_booking_provider
    return [] unless provider
    NextAvailableSlotFinder.call(provider: provider, duration_min: 30, from: from, limit: limit)
                           .map { |iso| Time.zone.parse(iso) }
  rescue StandardError => e
    Rails.logger.warn("[WebChat] open_times failed: #{e.class}: #{e.message}")
    []
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
    when_str = fmt_slot(appt.start_time)
    intake   = intake_link_for(appt.patient)
    if af?
      lines = [ "Jy is bespreek vir #{when_str} 🎉", "Ek het 'n bevestiging na jou WhatsApp gestuur." ]
      lines << "Voltooi asseblief jou veilige aanmeldingsvorm voor jou besoek — dit neem omtrent " \
               "5 minute, papierloos en privaat 🔐: #{intake}" if intake
      lines << "Ons is by Office Park, h/v Doreen- en Lawrencestraat, Amorosa, Roodepoort — " \
               "#{WhatsappStandardMessages::MAP_LINK}. Ons sien uit daarna om jou te sien! 🌸"
    else
      lines = [ "You're all booked for #{when_str} 🎉", "I've sent a confirmation to your WhatsApp." ]
      lines << "Please complete your secure intake form before your visit — about 5 minutes, " \
               "paperless and private 🔐: #{intake}" if intake
      lines << "We're at Office Park, cnr Doreen & Lawrence Rd, Amorosa, Roodepoort — " \
               "#{WhatsappStandardMessages::MAP_LINK}. We look forward to seeing you! 🌸"
    end
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
    if af?
      existing ? "Jy is reeds bespreek vir *#{fmt_slot(existing.start_time)}* 😊 Niks verder nodig nie — wil jy dit verander?" :
                 "Jy is reeds by ons bespreek 😊 Wil jy iets verander?"
    else
      existing ? "You're already booked in for *#{fmt_slot(existing.start_time)}* 😊 Nothing more to do — would you like to change it?" :
                 "You're already booked in with us 😊 Would you like to change anything?"
    end
  end

  def recoverable_reply(status, date)
    base = recoverable_base(status)
    from = [ (Time.zone.parse("#{date} 00:00") rescue Time.current), Time.current ].max
    slots = open_times(from: from, limit: 3) # structured Times so we can format them in the right language
    if slots.any?
      listed = slots.each_with_index.map { |t, i| "#{i + 1}. #{fmt_slot(t)}" }.join("\n")
      af? ? "#{base} Hier is die volgende beskikbare tye:\n#{listed}\nWatter een pas jou?" :
            "#{base} Here are the next available times:\n#{listed}\nWhich suits you?"
    else
      af? ? "#{base} Kan jy 'n ander dag voorstel, dan kry ek die naaste tyd?" :
            "#{base} Could you suggest another day and I'll find the closest slot?"
    end
  end

  def recoverable_base(status)
    en = {
      outside_working_hours: "That time is outside our hours — we're open Monday to Friday, 8am–5pm.",
      public_holiday:        "We're closed that day (we're closed on weekends and public holidays).",
      slot_taken:            "Ah, that slot was just taken.",
      too_soon:              "That's a little too soon for us to prepare for you.",
      after_hours_today:     "We've closed for today, but I'd love to get you booked."
    }
    af = {
      outside_working_hours: "Daardie tyd is buite ons ure — ons is oop Maandag tot Vrydag, 8vm–5nm.",
      public_holiday:        "Ons is daardie dag gesluit (ons is gesluit oor naweke en op openbare vakansiedae).",
      slot_taken:            "Ag, daardie tyd is nou net geneem.",
      too_soon:              "Dit is 'n bietjie te gou vir ons om vir jou voor te berei.",
      after_hours_today:     "Ons het vir vandag gesluit, maar ek sal jou graag bespreek."
    }
    (af? ? af : en)[status] || (af? ? "Dit het nie heeltemal gewerk nie." : "That didn't quite work.")
  end

  def next_slots(date)
    from = (Date.parse(date.to_s) rescue Date.current)
    AvailabilityService.new.next_available_slots(from_date: from, limit: 3)
  rescue StandardError
    []
  end
end

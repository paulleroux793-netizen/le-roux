require "net/http"
require "base64"

class WhatsappService
  class Error < StandardError; end

  # Supported MIME types for Claude document API.
  SUPPORTED_MEDIA_TYPES = %w[application/pdf image/jpeg image/png image/gif image/webp].freeze

  # Payloads sent by WhatsApp quick-reply buttons in the confirmation request.
  # When a patient taps a button Twilio delivers these as the inbound Body.
  BUTTON_CONFIRM_PAYLOAD    = "CONFIRM APPOINTMENT".freeze
  BUTTON_RESCHEDULE_PAYLOAD = "RESCHEDULE APPOINTMENT".freeze

  def initialize
    @ai = nil
    @templates = nil
  end

  # Extract media attachment metadata from Twilio webhook params.
  # Returns an array of { url:, content_type: } hashes (one per media item).
  # Only includes MIME types the Claude API can process.
  def self.extract_media_attachments(twilio_params)
    num_media = twilio_params["NumMedia"].to_i
    return [] if num_media.zero?

    (0...num_media).filter_map do |i|
      url = twilio_params["MediaUrl#{i}"]
      content_type = twilio_params["MediaContentType#{i}"]
      next unless url.present? && SUPPORTED_MEDIA_TYPES.include?(content_type)

      { url: url, content_type: content_type }
    end
  end

  # Main entry point: handle an incoming WhatsApp message.
  # Returns { response:, intent:, entities: }, OR nil if the conversation is
  # currently in reception-takeover standby (AI paused for X hours after a
  # human reply). When paused we still persist the inbound message and tag
  # the conversation needs_review so reception sees there's a fresh inbound;
  # no AI reply is generated.
  # Normalises common WhatsApp shorthand BEFORE downstream AI classification.
  # The classifier was missing "tmrw" / "tmr" / "tomoz" → tomorrow which led
  # to date entity extraction silently failing on casual messages.
  # Conservative list — only normalises unambiguous shortcuts; doesn't touch
  # full English/Afrikaans words.
  CASUAL_NORMALISATIONS = {
    /\btmrw\b/i  => "tomorrow",
    /\btmr\b/i   => "tomorrow",
    /\btomoz\b/i => "tomorrow",
    /\bnxt\b/i   => "next",
    /\bcleanin'?\b/i => "cleaning",
    /\bbookin'?\b/i  => "booking",
    /\bappt\b/i  => "appointment"
  }.freeze

  def normalize_casual_language(text)
    return text if text.blank?
    out = text.dup
    CASUAL_NORMALISATIONS.each { |re, sub| out.gsub!(re, sub) }
    out
  end

  def handle_incoming(from:, message:, twilio_params: {}, media_attachments: [])
    # Remember which sender the patient messaged. Subsequent outbound from this
    # service instance (booking confirmations, flagged alerts) uses the same
    # number so sandbox traffic stays on sandbox (free for testing) and
    # production traffic stays on production.
    @inbound_to = twilio_params["To"] || twilio_params[:To]

    # Normalise casual shorthand so the classifier reliably extracts dates
    # like "tmrw 9am" → "tomorrow 9am". The original text is still preserved
    # in twilio_params["Body"] for auditing if needed.
    message = normalize_casual_language(message)

    patient = find_or_create_patient(from)
    conversation = find_or_create_conversation(patient)

    # Reception takeover: if AI is on standby, log the inbound and bail.
    # See CODE_LOCKED_GUARDRAILS §8.2.
    if conversation.ai_paused?
      Rails.logger.info(
        "[WhatsApp] AI paused on conversation ##{conversation.id} until " \
        "#{conversation.ai_paused_until.iso8601} — saving inbound, skipping AI."
      )
      conversation.add_message(role: "user", content: message, timestamp: Time.current)
      tag_needs_review(conversation)
      return nil
    end

    # Path B (after-hours-only AI): during business hours, the AI does not
    # auto-reply. Reception handles the dashboard manually. We still persist
    # the inbound + tag the conversation so reception sees the message.
    # Outside business hours (incl. weekends + public holidays), AI takes
    # over fully. Configured via ai_mode in practice_config.yml.
    if !PracticeConfig.ai_active_during_business_hours? && currently_within_working_hours?
      Rails.logger.info(
        "[WhatsApp] AI off during business hours (Path B) — saving inbound on " \
        "conversation ##{conversation.id} for reception to handle manually."
      )
      conversation.add_message(role: "user", content: message, timestamp: Time.current)
      tag_needs_review(conversation)
      # Notify reception via SMS/email so they know there's a fresh inbound.
      send_business_hours_inbound_alert(patient, conversation, message)
      return nil
    end

    # Detect and persist language from the first message

    # If the patient sent media (image/PDF) and has a pending_confirmation
    # whitening appointment, tag the conversation deposit_proof_received so
    # staff can verify + flip status to scheduled.
    if media_attachments.present? && conversation
      pending = patient.appointments.where(status: :pending_confirmation)
                       .where("LOWER(notes) LIKE ?", "%whitening deposit%")
                       .exists?
      if pending
        tags = Array(conversation.tags || [])
        unless tags.include?("deposit_proof_received")
          conversation.update(tags: (tags + ["deposit_proof_received"]).uniq)
          Rails.logger.info("[Whitening] Deposit proof media received for patient ##{patient.id}; conversation ##{conversation.id} tagged.")
          send_flagged_alert(patient, "WHITENING DEPOSIT PROOF received — verify & confirm appointment")
        end
      end
    end
    detect_and_persist_language(conversation, message)

    # Button-reply fast path — intercepts quick-reply payloads before the AI
    # so "CONFIRM APPOINTMENT" / "RESCHEDULE APPOINTMENT" never waste an API call.
    button_result = build_button_payload_result(message: message, conversation: conversation)
    if button_result
      persist_exchange(conversation, message, button_result[:response])
      handle_intent(button_result, patient, conversation)
      return button_result
    end

    fast_path_result = build_local_result(message: message, conversation: conversation)

    if fast_path_result
      persist_exchange(conversation, message, fast_path_result[:response])
      handle_intent(fast_path_result, patient, conversation)
      return fast_path_result
    end

    # Process through AI brain
    downloaded = download_media_attachments(media_attachments)

    result = ai_service.process_message(
      message: message,
      conversation: conversation,
      patient: patient,
      media_attachments: downloaded
    )

    # Route based on detected intent
    handle_intent(result, patient, conversation)
    # Safety net: if handle_intent's response still claims a booking but the
    # DB has no new Appointment for this patient, override. Guards against
    # AI classifier misses (entities missing date/time) and prompt leakage.
    verify_booking_response_consistency(result, patient, conversation)
    # Safety net #2: if the AI could not give a useful answer, flag the
    # conversation for staff review and swap the patient message to a
    # "human will follow up" template.
    verify_response_is_actionable(result, patient, conversation)

    # Persist the exchange after intent handling so the stored response
    # reflects any rewrite that handle_intent may have applied (e.g.
    # booking-claim rewrites, after-hours blocks, nil on successful booking).
    persist_exchange(conversation, message, result[:response]) if conversation

    result
  rescue AiService::Error => e
    Rails.logger.warn("[WhatsApp] AI unavailable, using fallback response: #{e.message}")

    fallback_result = build_fallback_result(message: message, conversation: conversation)

    persist_exchange(conversation, message, fallback_result[:response]) if conversation

    fallback_result
  end

  private
  # --- Booking Safety Net ---

  # Runs after handle_intent. If the AI's response text looks like a booking
  # claim ("I've booked...", "securing this appointment...", "booking noted")
  # but no Appointment row was created for this patient in the last 15 seconds,
  # rewrite the response to the failure fallback. Prevents false confirmations
  # regardless of classifier intent accuracy.
  def verify_booking_response_consistency(result, patient, conversation)
    return if result[:response].blank?
    return unless looks_like_booking_claim?(result[:response])
    return if patient_has_recent_appointment?(patient)
    lang_code = (conversation && conversation.language.presence) || "en"
    Rails.logger.warn(
      "[WhatsApp] Booking claim in response but no recent Appointment for patient " \
      "##{patient.id}; overriding. lang=#{lang_code.inspect}"
    )
    result[:response] = BOOKING_FAILED_FALLBACK[lang_code] || BOOKING_FAILED_FALLBACK["en"]
  end

  # Broader match than BOOKING_CLAIM_PHRASES — covers confirmation-flavored
  # text the AI sometimes emits even when intent classifier said faq/other.
  BOOKING_CLAIM_PATTERNS = [
    /\bbooked you in\b/i,
    /\bbooking (noted|confirmed|complete|secured|locked)\b/i,
    /\bsecur(ing|ed) (this|that|your) appointment\b/i,
    /\bsecured your slot\b/i,
    /\bflag(ging|ged) that slot\b/i,
    /\block(ing|ed)? (it|that|this) in\b/i,
    /\ball set for\b/i,
    /\bappointment confirmed\b/i,
    /\bhere'?s (a )?summary of what i have\b/i,
    /\byou'?re (booked|confirmed|locked in)\b/i,
    /\bi'?ve (booked|scheduled) you\b/i,
    /\brequested slot:\b/i,
    /✅\s*\*?appointment\s+confirmed\*?/i
  ].freeze

  def looks_like_booking_claim?(response)
    return false if response.blank?
    txt = response.to_s
    BOOKING_CLAIM_PATTERNS.any? { |re| re.match?(txt) } || booking_claim?(txt)
  end

  # --- Staff-review safety net ---

  # Patterns suggesting the AI could not answer the query usefully. When
  # matched, verify_response_is_actionable escalates to staff review.
  UNCERTAINTY_PATTERNS = [
    # Core exhaustion / out-of-scope signals
    /system is a bit busy/i,
    /\bi'?m an AI (assistant|bot)\b/i,
    /\bi'?m not sure\b/i,
    /\bi'?m not able to (answer|assist with|access)\b/i,
    # "don't have access" family
    /\bi don'?t (have|know) (that|the) (answer|information)\b/i,
    /\bi don'?t have access to\b/i,
    /\bi don'?t have (the|that) (context|details?)\b/i,
    /\bnot able to access\b/i,
    /that'?s outside (my|our) scope/i,
    # Explicit hand-off phrasing
    /\blet me get back to you\b/i,
    /\bi'?ll need to check with (the team|our team|the practice)\b/i,
    /\bi'?ll need to have our team\b/i,
    /\bi'?ll (need to )?flag (this|that|your|it|the)\b/i,
    /\bflag (this|that|it|the|your message|your query) (for|message|question|to|as)?\b/i,
    /\bfor staff review\b/i,
    /\bmake sure (our team|the practice|someone)\b/i,
    # "(our) team will come back / comes back / gets back"
    /\b(our team|the practice|someone from the practice|the team) (will|can|comes?|gets?) (come back|back|follow up|get back|reach out)\b/i,
    /\b(come|comes?|get|gets?) back to you personally\b/i,
    /\bfollow up (with you )?as soon as the practice opens\b/i,
    /cannot answer that (query|question)/i,
    # Non-patient handoff phrasings (suppliers, sales reps, recruiters)
    /\bpass(ing)? this (on|along)\b/i,
    /\b(reception|admin|practice) team\s+(will|can|comes?|gets?)\b/i,
    /\b(i'?m|i am) (the|a) booking assistant\b/i,
    /\b(not able|unable) to help with (supplier|sales|delivery|meeting|partnership)/i,
    /\bI'?ll have (our|the) team get back/i
  ].freeze

  def verify_response_is_actionable(result, patient, conversation)
    return if result[:response].blank?
    return unless response_signals_uncertainty?(result[:response])
    # Patient-facing rewrite + flag the conversation + notify staff.
    flag_conversation_for_staff_review(conversation, patient, original_response: result[:response])
    lang_code = (conversation && conversation.language.presence) || "en"
    result[:response] = STAFF_REVIEW_FALLBACK[lang_code] || STAFF_REVIEW_FALLBACK["en"]
  end

  def response_signals_uncertainty?(response)
    txt = response.to_s
    UNCERTAINTY_PATTERNS.any? { |re| re.match?(txt) }
  end

  # Tag a conversation needs_review without the staff-alert side effect.
  # Used for the reception-takeover paused path where the patient has just
  # sent an inbound message but the AI is on standby — reception already
  # owns the conversation, so we just want a visible flag in the dashboard.
  def tag_needs_review(conversation)
    return unless conversation
    tags = Array(conversation.tags || [])
    return if tags.include?("needs_review")
    conversation.update(tags: (tags + ["needs_review"]).uniq)
  rescue StandardError => e
    Rails.logger.warn("[WhatsApp] tag_needs_review failed: #{e.class}: #{e.message}")
  end

  def flag_conversation_for_staff_review(conversation, patient, original_response:)
    return unless conversation
    tags = Array(conversation.tags || [])
    unless tags.include?("needs_review")
      conversation.update(tags: (tags + ["needs_review"]).uniq)
    end
    Rails.logger.warn(
      "[WhatsApp] Flagged conversation ##{conversation.id} for staff review. " \
      "AI said: #{original_response.to_s[0..180].inspect}"
    )
    send_flagged_alert(patient, "WhatsApp query needs manual response: #{original_response.to_s[0..200]}")
  rescue StandardError => e
    Rails.logger.error("[WhatsApp] flag_conversation_for_staff_review failed: #{e.class}: #{e.message}")
  end

  def whitening_already_sent?(conversation)
    return false unless conversation
    msgs = conversation.messages || []
    msgs.any? do |m|
      role = m.is_a?(Hash) ? (m["role"] || m[:role]) : nil
      content = m.is_a?(Hash) ? (m["content"] || m[:content] || "") : ""
      role == "assistant" && content.to_s.include?("Biolase laser teeth whitening")
    end
  rescue StandardError
    false
  end
  def patient_has_recent_appointment?(patient)
    return false unless patient
    patient.appointments.where("created_at > ?", 5.minutes.ago).exists?
  end


  # --- Patient Management ---

  def find_or_create_patient(phone)
    Patient.find_or_create_by!(phone: normalize_phone(phone)) do |p|
      p.first_name = "WhatsApp"
      p.last_name = "Patient"
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("[WhatsApp] Failed to find/create patient for #{phone}: #{e.message}")
    # Try find again in case of race condition
    Patient.find_by!(phone: normalize_phone(phone))
  end

  def find_or_create_conversation(patient)
    # Reuse active conversation if one exists (within last 24 hours)
    conversation = patient.conversations
      .where(channel: "whatsapp", status: "active")
      .where("updated_at > ?", 24.hours.ago)
      .order(updated_at: :desc)
      .first

    conversation || patient.conversations.create!(
      channel: "whatsapp",
      status: "active",
      messages: [],
      started_at: Time.current,
      language: patient.preferred_language.presence
    )
  end

  # --- Intent Routing ---

  def handle_intent(result, patient, conversation)
    # If the classifier did not tag this as "book" but extracted a concrete
    # date+time, treat it as a booking attempt. Otherwise the AI's free text
    # may claim a confirmation ("Here's a summary...") even though no
    # Appointment will be persisted. Forcing the booking path lets
    # attempt_booking actually write to DB (or fail cleanly via the fallback).
    entities = result[:entities] || {}
    if result[:intent] != "book" && entities[:date].present? && entities[:time].present?
      Rails.logger.info(
        "[WhatsApp] Forcing intent=book (classifier said #{result[:intent].inspect}; " \
        "entities have date=#{entities[:date].inspect} time=#{entities[:time].inspect})"
      )
      result[:intent] = "book"
    end

    case result[:intent]
    when "book"
      handle_booking(result, patient, conversation)
    when "reschedule"
      handle_reschedule(result, patient, conversation)
    when "cancel"
      handle_cancellation(result, patient, conversation)
    when "confirm"
      handle_confirmation(patient)
    when "confirm_upcoming"
      handle_upcoming_confirmation(patient)
    when "urgent"
      handle_urgent(patient, conversation)
    end
  rescue StandardError => e
    Rails.logger.error("[WhatsApp] Intent handling error (#{result[:intent]}): #{e.message}")
    # Don't re-raise — the AI response is already set, intent handling is best-effort
  end

  # --- Booking Flow ---
  #
  # IMPORTANT — the AI generates `result[:response]` *before* this
  # handler runs, so the bot will happily compose "Perfect! I have
  # you booked..." text even when no Appointment row gets persisted
  # (slot mismatch, Google API error, missing credentials, etc).
  # We mutate `result[:response]` in place when the booking didn't
  # actually land so the controller's TwiML reply matches reality.
  # The hash is shared by reference with WhatsappController, which
  # reads `result[:response]` *after* this handler returns.

  BOOKING_FAILED_FALLBACK = {
    "en" => "Sorry — that slot isn't available (someone else may have just " \
            "taken it, or it's outside our working hours). We're open Monday " \
            "to Friday, 8am–5pm. Could you try a different day or time?",
    "af" => "Jammer — daardie tyd is nie beskikbaar nie (iemand anders het " \
            "dalk pas bespreek, of dit val buite ons werksure). Ons is oop " \
            "Maandag tot Vrydag, 8vm–5nm. Kan jy 'n ander dag of tyd probeer?"
  }.freeze

  AFTER_HOURS_TODAY_BLOCKED = {
    "en" => "Hi there! Our practice is currently closed. 🕐\n\n" \
            "We're open *Monday to Friday, 8am–5pm*, and we don't have dentists " \
            "on duty outside those hours. If this is a dental emergency, please " \
            "share your name, contact number and a short description — we always " \
            "prioritise emergencies and will book you into the very first " \
            "available slot the moment we reopen. 😊\n\n" \
            "Otherwise, send me your preferred date and time (during business hours) " \
            "and I'll get you booked in.",
    "af" => "Hallo! Ons praktyk is tans gesluit. 🕐\n\n" \
            "Ons is oop *Maandag tot Vrydag, 8vm–5nm*, en het nie tandartse " \
            "na-ure werksaam nie. Indien dit 'n tandheelkundige noodgeval is, " \
            "stuur asseblief jou naam, kontaknommer en 'n kort beskrywing — " \
            "ons prioritiseer altyd noodgevalle en bespreek jou in op die eerste " \
            "beskikbare tyd sodra ons weer oopmaak. 😊\n\n" \
            "Andersins, stuur my jou voorkeurdatum en -tyd (binne werksure) " \
            "en ek kry jou bespreek."
  }.freeze
  # SA public holidays + statutory substitutes are now sourced from
  # config/practice_config.yml via PracticeConfig.public_holiday_dates.
  # Add new dates by editing the YAML — no Ruby change required.

  PUBLIC_HOLIDAY_BLOCKED = {
    "en" => "Unfortunately we're closed on that day. We're open *Monday to Friday, " \
            "8am–5pm* (excluding public holidays and weekends). Could you try a " \
            "different day? I'm happy to book the next available working day.",
    "af" => "Jammer, ons is op daardie dag gesluit. Ons is oop *Maandag tot Vrydag, " \
            "8vm–5nm* (uitgesluit openbare vakansiedae en naweke). Kan jy 'n ander " \
            "dag probeer? Ek bespreek graag die volgende beskikbare werksdag."
  }.freeze

  # Fired when the requested slot itself is outside business hours (not just
  # the message arrival time). The practice is never open at 06:00 or 18:00,
  # so booking those slots is hard-rejected. See attempt_booking.
  OUTSIDE_WORKING_HOURS_BLOCKED = {
    "en" => "Sorry — that time is outside our working hours. We're open " \
            "*Monday to Friday, 8am–5pm*. Could you pick a time within those hours? " \
            "I'm happy to suggest the next available slot.",
    "af" => "Jammer — daardie tyd is buite ons werksure. Ons is oop " \
            "*Maandag tot Vrydag, 8vm–5nm*. Kan jy 'n tyd binne werksure kies? " \
            "Ek stel graag die volgende beskikbare gleuf voor."
  }.freeze

  # Address / map / directions sourced from PracticeConfig (single source of
  # truth). External callers (e.g. ConfirmationService) reference these
  # constants — keep them as delegators so we don't need to update every
  # touchpoint at once.
  PRACTICE_ADDRESS    = PracticeConfig.full_address
  PRACTICE_MAP_LINK   = PracticeConfig.map_link
  PRACTICE_DIRECTIONS = PracticeConfig.directions

  # Appointment duration mapping is now in config/practice_config.yml.
  # PracticeConfig.duration_for(treatment) handles alias matching and the
  # default fallback. See duration_for_treatment further down.

  RESCHEDULE_REJECTED = {
    "en" => "Sorry — that slot isn't available or falls outside our working hours. Would you like to try a different day or time?",
    "af" => "Jammer — daardie tyd is nie beskikbaar nie of val buite ons werksure. Wil jy 'n ander dag of tyd probeer?"
  }.freeze
  # Whitening deterministic info message (EN + AF) is now sourced from
  # config/practice_config.yml under services[whitening].full_info_message.
  # Read via PracticeConfig.whitening[:full_info_message][lang.to_sym].
  # Use whitening_info(lang) helper below — it falls back to EN if the
  # configured language is missing.
  WHITENING_INFO = {
    "en" => PracticeConfig.whitening.dig(:full_info_message, :en).to_s.strip,
    "af" => PracticeConfig.whitening.dig(:full_info_message, :af).to_s.strip
  }.freeze


  BOOKING_CLAIM_PHRASES = [
    # English
    "i have you booked",
    "you're booked",
    "youre booked",
    "you are booked",
    "you're confirmed",
    "you are confirmed",
    "appointment is confirmed",
    "appointment is booked",
    "i've booked",
    "ive booked",
    "i've scheduled",
    "ive scheduled",
    "all set for",
    "see you on",
    "see you at",
    # Afrikaans
    "jy is bespreek",
    "afspraak is bevestig",
    "afspraak is bespreek",
    "ek het jou bespreek",
    "ek het jou ingeskryf",
    "sien jou op",
    "sien jou om",
    "alles is reg vir"
  ].freeze

  def handle_booking(result, patient, conversation)
    entities = result[:entities] || {}
    date = entities[:date]
    time = entities[:time]
    lang = conversation&.language || "en"

    Rails.logger.info(
      "[WhatsApp] handle_booking intent=book date=#{date.inspect} " \
      "time=#{time.inspect} treatment=#{entities[:treatment].inspect} " \
      "name=#{entities[:name].inspect}"
    )

    # Update the patient's name if they provided one and they still
    # have the placeholder "WhatsApp Patient" name.
    update_patient_name(patient, entities[:name]) if entities[:name].present?

    booking_result = nil
    if date.present? && time.present?
      booking_result = attempt_booking(patient, date, time, entities[:treatment], language: lang)
    end

    # After-hours booking for today — blocked, rewrite response
    if booking_result == :after_hours_today
      lang = conversation&.language || "en"
      result[:response] = AFTER_HOURS_TODAY_BLOCKED[lang] || AFTER_HOURS_TODAY_BLOCKED["en"]
      return
    end
    # Public holiday → always blocked (never bookable).
    if booking_result == :public_holiday
      result[:response] = PUBLIC_HOLIDAY_BLOCKED[lang] || PUBLIC_HOLIDAY_BLOCKED["en"]
      return
    end
    # Slot itself is outside working hours (e.g. 06:00 or 18:00). Hard-reject.
    # See attempt_booking — distinct from message-arrived-after-hours.
    if booking_result == :outside_working_hours
      result[:response] = OUTSIDE_WORKING_HOURS_BLOCKED[lang] || OUTSIDE_WORKING_HOURS_BLOCKED["en"]
      return
    end

    if booking_result.is_a?(Appointment)
      # Confirmation was already sent via send_booking_confirmation_message.
      # Clear the AI's response so the job doesn't send a second conflicting message.
      result[:response] = nil
      return
    end

    # Booking attempted but failed (slot conflict, past time, rescue path).
    # Unconditionally rewrite the AI response — never trust that booking_claim?
    # caught every possible confirmation phrase. DB is source of truth; if no
    # Appointment was persisted, the patient does NOT have a booking.
    if date.present? && time.present? && booking_result.nil?
      Rails.logger.warn(
        "[WhatsApp] Booking attempted but failed; overriding AI response to prevent " \
        "false confirmation. date=#{date.inspect} time=#{time.inspect}"
      )
      result[:response] = BOOKING_FAILED_FALLBACK[lang] || BOOKING_FAILED_FALLBACK["en"]
      return
    end

    # We did NOT persist an Appointment — either because the classifier
    # didn't normalize the date/time (relative phrases like "Friday")
    # or because attempt_booking failed. If the AI's free text is
    # *claiming* a booking, rewrite it so the controller's TwiML reply
    # matches reality. If it's still gathering info ("what day works?"),
    # leave it alone.
    if booking_claim?(result[:response])
      Rails.logger.warn(
        "[WhatsApp] AI claimed a booking but no Appointment was persisted; " \
        "rewriting response. date=#{date.inspect} time=#{time.inspect}"
      )
      lang = conversation&.language || "en"
      result[:response] = BOOKING_FAILED_FALLBACK[lang] || BOOKING_FAILED_FALLBACK["en"]
    end
  end

  def booking_claim?(response)
    return false if response.blank?

    text = response.downcase
    BOOKING_CLAIM_PHRASES.any? { |phrase| text.include?(phrase) }
  end

  # Returns the persisted Appointment on success, or nil on any
  # failure. Never raises — the caller relies on the nil sentinel.
  #
  # The local Appointment table is the source of truth — the in-app
  # FullCalendar reads from it directly. Google Calendar is a
  # best-effort secondary sync; if creds aren't set or the API
  # errors, we still persist locally so the booking shows up in
  # the in-app calendar. The previous implementation made Google
  # the gatekeeper, so any creds/API issue silently swallowed the
  # booking with no row written and no error surfaced.
  def attempt_booking(patient, date, time, treatment, language: "en")
    start_time = Time.zone.parse("#{date} #{time}")
    duration = duration_for_treatment(treatment)
    end_time = start_time + duration
    reason = treatment&.capitalize || "Consultation"

    # 30-minute booking buffer (configurable in practice_config.yml).
    # Patients need travel time + intake form completion; booking "right now"
    # cascades into the practice running late for the rest of the day.
    # See CODE_LOCKED_GUARDRAILS §1.7. Staff bookings via the dashboard
    # bypass this rule — reception can squeeze in walk-ins.
    buffer = PracticeConfig.booking_buffer_minutes.minutes
    earliest_bookable = Time.current + buffer
    if start_time <= earliest_bookable
      Rails.logger.info(
        "[WhatsApp] Booking rejected: within #{PracticeConfig.booking_buffer_minutes}-min buffer " \
        "(start=#{start_time}, earliest=#{earliest_bookable})"
      )
      return nil
    end
    if public_holiday?(start_time.to_date)
      Rails.logger.info("[WhatsApp] Booking rejected: #{start_time.to_date} is a SA public holiday")
      return :public_holiday
    end

    # Two distinct after-hours checks (separated 2026-05-12 per stress-test
    # audit — the previous code conflated these and accepted future-dated
    # slots outside working hours as pending_confirmation, leading to bookings
    # at 18:00 and 06:00 being confirmed when the practice isn't open then):
    #
    #   slot_outside_hours    = the requested slot is NEVER a valid slot
    #                           (e.g. 18:00 on a Friday, 06:00 on Tuesday).
    #                           → REJECT unconditionally.
    #
    #   message_arrived_after_hours = the patient messaged us outside business
    #                           hours but is asking for a slot WITHIN business
    #                           hours. Booking is held as pending_confirmation
    #                           until reception verifies + confirms in the morning.
    slot_outside_hours = !slot_within_working_hours?(start_time, end_time)
    if slot_outside_hours
      Rails.logger.info("[WhatsApp] Booking rejected: slot outside working hours (#{start_time})")
      return :outside_working_hours
    end

    message_arrived_after_hours = !currently_within_working_hours?
    if message_arrived_after_hours && start_time.to_date == Date.current
      # Message at e.g. 19:00 today asking for 8am today (already passed) —
      # historically captured the case where the patient wants TODAY but
      # we received the message too late to confirm. Practical effect: rejection.
      Rails.logger.info("[WhatsApp] Booking rejected: after hours for today (#{start_time})")
      return :after_hours_today
    end

    if message_arrived_after_hours
      Rails.logger.info("[WhatsApp] Message arrived after-hours for future slot — pending confirmation (#{start_time})")
    end

    if slot_conflicts_locally?(start_time, end_time)
      Rails.logger.info("[WhatsApp] Booking rejected: conflicts with existing appointment (#{start_time})")
      return nil
    end

    # Whitening is paid via R2,000 deposit upfront. Until proof of payment
    # lands, the appointment is :pending_confirmation — the diary slot is
    # held but staff verify payment before the patient is "locked in".
    is_whitening = treatment.to_s.downcase.match?(/whitening|biolase|bleiking|tandebleiking|bleach/)
    base_status = if message_arrived_after_hours
                    :pending_confirmation
                  elsif is_whitening
                    :pending_confirmation
                  else
                    :scheduled
                  end
    booking_notes = is_whitening ? "awaiting R2,000 whitening deposit" : nil

    appointment = patient.appointments.create!(
      start_time: start_time,
      end_time: end_time,
      reason: reason,
      status: base_status,
      notes: booking_notes
    )

    # Create a confirmation log so the reminders page tracks this
    # booking from the moment it's created. The outcome is nil
    # until the patient replies to the WhatsApp confirmation.
    appointment.confirmation_logs.create!(
      method: "whatsapp",
      outcome: nil,
      attempts: 1,
      flagged: false
    )

    # sync_to_google_calendar(appointment, patient, reason) # Disabled 2026-04-24: local DB is source of truth, Google mirror no longer used
    send_confirmation_template(patient, appointment, after_hours: message_arrived_after_hours, language: language)
    send_confirmation_email(appointment)
    send_confirmation_sms(appointment)

    # Path B: report after-hours bookings to the main WhatsApp line so
    # reception sees the activity in web.whatsapp.com without logging
    # into the dashboard. Only fires for AI-driven bookings (this method);
    # staff dashboard bookings already happen with reception in the loop.
    summary = "AI booked #{patient.full_name} for #{reason} on " \
              "#{appointment.start_time.strftime('%a %-d %b at %H:%M')}" +
              (message_arrived_after_hours ? " (pending confirmation — booked after hours)" : "") +
              (is_whitening ? " (awaiting R2,000 deposit)" : "")
    report_to_main_line("BOOKING", patient: patient, summary: summary)

    appointment
  rescue StandardError => e
    Rails.logger.error("[WhatsApp] Booking failed: #{e.class}: #{e.message}")
    nil
  end

  # Working-hours check against DoctorSchedule. Rejects bookings
  # outside the doctor's hours, on closed days, or that overlap
  # the lunch break.
  # True for any day we do not accept bookings on: weekends (Saturday/Sunday)
  # or any South African public holiday.
  def public_holiday?(date)
    return true if date.wday == 0 || date.wday == 6
    PracticeConfig.public_holiday_dates.include?(date)
  end
  def slot_within_working_hours?(start_time, end_time)
    schedule = DoctorSchedule.for_day(start_time.wday)
    return false unless schedule

    schedule.working?(start_time) && schedule.working?(end_time - 1.minute)
  end

  # Local conflict check — any existing non-cancelled appointment
  # whose time range overlaps the requested slot.
  # Pass exclude_appointment_id when rescheduling to avoid the
  # appointment conflicting with its own current slot.
  def slot_conflicts_locally?(start_time, end_time, exclude_appointment_id: nil)
    query = Appointment
      .where.not(status: :cancelled)
      .where("start_time < ? AND end_time > ?", end_time, start_time)
    query = query.where.not(id: exclude_appointment_id) if exclude_appointment_id
    query.exists?
  end

  # Best-effort Google Calendar sync. Failure here does NOT roll
  # back the local Appointment — the patient is still booked in
  # the in-app calendar. If creds are missing or the API errors,
  # we log and move on. A future job can backfill google_event_id
  # for unsynced appointments.
  def sync_to_google_calendar(appointment, patient, reason)
    calendar = GoogleCalendarService.new
    event_id = calendar.create_event(
      patient: patient,
      start_time: appointment.start_time,
      end_time: appointment.end_time,
      reason: reason
    )
    appointment.update_column(:google_event_id, event_id) if event_id
  rescue StandardError => e
    Rails.logger.warn("[WhatsApp] Google Calendar sync skipped: #{e.class}: #{e.message}")
  end

  # --- Reschedule Flow ---

  def handle_reschedule(result, patient, conversation)
    entities = result[:entities] || {}
    appointments = patient.appointments.upcoming

    return if appointments.empty?

    # Bail early only when we have neither a date nor a time.
    # A time-only response ("same time at 2pm") is valid — we'll
    # find the next available date for that time below.
    return unless entities[:date].present? || entities[:time].present?

    appointment = appointments.first
    duration = appointment.end_time - appointment.start_time
    lang = conversation&.language || "en"

    new_start = if entities[:date].present? && entities[:time].present?
      Time.zone.parse("#{entities[:date]} #{entities[:time]}")
    elsif entities[:time].present?
      # Patient gave a time but no specific date — find the next available
      # working day where that time slot is free.
      next_date = next_available_date_for_time(entities[:time], duration)
      unless next_date
        result[:response] = RESCHEDULE_REJECTED[lang] || RESCHEDULE_REJECTED["en"]
        return
      end
      Time.zone.parse("#{next_date} #{entities[:time]}")
    else
      # Date only, no time — ask the AI to gather the time; bail for now
      return
    end

    new_end = new_start + duration

    # Guardrail: new slot must be in the future
    unless new_start > Time.current
      result[:response] = RESCHEDULE_REJECTED[lang] || RESCHEDULE_REJECTED["en"]
      return
    end

    # Guardrail: new slot must be within working hours
    unless slot_within_working_hours?(new_start, new_end)
      result[:response] = RESCHEDULE_REJECTED[lang] || RESCHEDULE_REJECTED["en"]
      Rails.logger.info("[WhatsApp] Reschedule rejected: outside working hours (#{new_start})")
      return
    end

    # Guardrail: new slot must not conflict with another appointment.
    # Exclude the appointment being moved — it's vacating the old slot.
    if slot_conflicts_locally?(new_start, new_end, exclude_appointment_id: appointment.id)
      result[:response] = RESCHEDULE_REJECTED[lang] || RESCHEDULE_REJECTED["en"]
      Rails.logger.info("[WhatsApp] Reschedule rejected: slot conflict (#{new_start})")
      return
    end

    # Local record is source of truth — update regardless of Google Calendar state
    appointment.update!(
      start_time: new_start,
      end_time: new_end,
      status: :scheduled
    )

    # Best-effort Google Calendar sync — failure does not roll back the local update
    if appointment.google_event_id
      begin
        GoogleCalendarService.new.reschedule_appointment(
          appointment.google_event_id,
          new_start: new_start
        )
      rescue StandardError => e
        Rails.logger.warn("[WhatsApp] Google Calendar reschedule sync skipped: #{e.message}")
      end
    end

    send_reschedule_template(patient, appointment)

    # Path B: report rescheduled bookings to the main line.
    report_to_main_line(
      "RESCHEDULE",
      patient: patient,
      summary: "AI rescheduled #{patient.full_name}'s appointment to #{appointment.start_time.strftime('%a %-d %b at %H:%M')}"
    )
  rescue StandardError => e
    Rails.logger.error("[WhatsApp] Reschedule failed: #{e.message}")
  end

  # --- Cancellation Flow ---

  def handle_cancellation(result, patient, conversation)
    appointments = patient.appointments.upcoming

    return if appointments.empty?

    appointment = appointments.first
    reason_category = extract_cancellation_reason(result)

    # Cancel locally first — Google Calendar sync is best-effort
    appointment.cancelled!

    if appointment.google_event_id
      begin
        GoogleCalendarService.new.cancel_appointment(
          appointment.google_event_id,
          reason_category: reason_category,
          reason_details: "Cancelled via WhatsApp"
        )
      rescue StandardError => e
        Rails.logger.warn("[WhatsApp] Google Calendar cancel sync skipped: #{e.message}")
      end
    end

    send_cancellation_template(patient, appointment)

    # Path B: report cancellations to the main line so reception can
    # consider whether to fill the freed slot from the waiting list.
    report_to_main_line(
      "CANCEL",
      patient: patient,
      summary: "AI cancelled #{patient.full_name}'s appointment on #{appointment.start_time.strftime('%a %-d %b at %H:%M')} — reason: #{reason_category}"
    )
  rescue StandardError => e
    Rails.logger.error("[WhatsApp] Cancellation failed: #{e.message}")
  end

  # --- Confirmation Flow ---

  def handle_confirmation(patient)
    appointment = patient.appointments
      .where(status: :scheduled)
      .where(start_time: Date.current.all_day)
      .first

    return unless appointment

    appointment.confirmed!

    appointment.confirmation_logs.create!(
      method: "whatsapp",
      outcome: "confirmed",
      attempts: 1,
      flagged: false
    )
  end

  # Confirms the patient's next upcoming appointment (used for button-reply
  # confirmations where the appointment may be tomorrow, not today).
  # The existing handle_confirmation targets same-day appointments for the
  # voice/manual-reply flow and is left unchanged.
  def handle_upcoming_confirmation(patient)
    appointment = patient.appointments
      .where(status: :scheduled)
      .where("start_time > ?", Time.current)
      .order(:start_time)
      .first

    return unless appointment

    appointment.confirmed!

    appointment.confirmation_logs.create!(
      method:   "whatsapp",
      outcome:  "confirmed",
      attempts: 1,
      flagged:  false,
      notes:    "Confirmed via WhatsApp button"
    )

    mark_appointment_confirmed_on_calendar(appointment)
  end

  # Detects whether the inbound message is a quick-reply button tap and
  # returns a pre-built result hash, bypassing the AI entirely.
  # Returns nil for any other message so the normal flow continues.
  def build_button_payload_result(message:, conversation:)
    lang   = conversation&.language || "en"
    body   = message.to_s.strip.upcase

    if body == BUTTON_CONFIRM_PAYLOAD
      response = lang == "af" ?
        "Uitstekend! Jou afspraak is bevestig. Ons sien jou môre! 😊" :
        "Great! Your appointment is confirmed. We'll see you tomorrow! 😊"
      { response: response, intent: "confirm_upcoming", entities: {} }

    elsif body == BUTTON_RESCHEDULE_PAYLOAD
      response = lang == "af" ?
        "Geen probleem! Stuur asseblief jou voorkeur datum en tyd en ons sal dit reël." :
        "No problem! Please send your preferred date and time and we'll arrange that for you."
      { response: response, intent: "reschedule", entities: {} }
    end
  end

  # Best-effort Google Calendar update when appointment is confirmed.
  def mark_appointment_confirmed_on_calendar(appointment)
    return unless appointment.google_event_id

    GoogleCalendarService.new.confirm_appointment(appointment.google_event_id)
  rescue StandardError => e
    Rails.logger.warn("[WhatsApp] Google Calendar confirm sync skipped: #{e.message}")
  end

  # --- Urgent Flow ---

  def handle_urgent(patient, conversation)
    # Flag for immediate follow-up
    send_flagged_alert(patient, "URGENT: Patient reported dental emergency via WhatsApp")
  end

  # --- Template Sending (best-effort) ---

  def send_confirmation_template(patient, appointment, after_hours: false, language: "en")
    # Send detailed booking confirmation with directions via free-form
    # message (within the 24-hour service window since the patient
    # just messaged us). Falls back to the Twilio template if the
    # free-form send fails.
    send_booking_confirmation_message(patient, appointment, after_hours: after_hours, language: language)
  rescue StandardError => e
    Rails.logger.warn("[WhatsApp] Booking confirmation message failed, trying template: #{e.message}")
    begin
      template_service&.send_confirmation(patient, appointment)
    rescue WhatsappTemplateService::Error => te
      Rails.logger.warn("[WhatsApp] Template fallback also failed: #{te.message}")
    end
  end

  # Sends the branded booking confirmation message with appointment
  # details and practice directions. Uses the free-form `send_text`
  # method since the patient is within the 24-hour service window.
  # Bilingual: responds in Afrikaans when language == "af".
  AFRIKAANS_DAYS   = %w[Sondag Maandag Dinsdag Woensdag Donderdag Vrydag Saterdag].freeze
  AFRIKAANS_MONTHS = %w[Januarie Februarie Maart April Mei Junie Julie Augustus September Oktober November Desember].freeze

  def localized_day_name(time, language)
    language == "af" ? AFRIKAANS_DAYS[time.wday] : time.strftime("%A")
  end

  def localized_date(time, language)
    if language == "af"
      "#{time.day} #{AFRIKAANS_MONTHS[time.month - 1]} #{time.year}"
    else
      time.strftime("%-d %B %Y")
    end
  end

  def send_booking_confirmation_message(patient, appointment, after_hours: false, language: "en")
    day_name  = localized_day_name(appointment.start_time, language)
    date_str  = localized_date(appointment.start_time, language)
    time_str  = appointment.start_time.strftime("%H:%M")
    # Treat as a new patient whenever this is their FIRST appointment
    # (regardless of whether the AI managed to extract their name yet).
    # Previously this checked Patient#auto_created_placeholder_profile? which
    # flipped to false the moment the AI extracted any name — meaning
    # "name=Test, new patient" got the returning-patient confirmation message
    # without the medical-aid + arrive-10-min-early addons. Stress test
    # audit 2026-05-12.
    is_new = patient.appointments.where.not(id: appointment.id).none?

    body = if language == "af"
      after_hours_notice = after_hours ?
        "\n\n⏳ Hierdie bespreking is na ure gemaak. Ons sal jou afspraak bevestig sodra die praktyk môreoggend oopmaak." : ""
      new_patient_addon = is_new ?
        "\n\nOnthou dat ons nie direk van mediesefonds eis nie. Pasiënte betaal by die praktyk en kan daarna terugeis met die staat wat ons verskaf.\n\nKom asseblief 10 minute vroeg aan sodat ons jou lêer kan voltooi." : ""

      <<~MSG.strip
        Jou afspraak is bespreek vir #{day_name}, #{date_str} om #{time_str}.#{after_hours_notice}

        #{PRACTICE_ADDRESS}
        Google Maps: #{PRACTICE_MAP_LINK}

        Aanwysings: #{PRACTICE_DIRECTIONS}#{new_patient_addon}

        As jy iets wil verander, antwoord net hier.
      MSG
    else
      after_hours_notice = after_hours ?
        "\n\n⏳ This booking was made after hours. We'll confirm your appointment first thing in the morning once we verify the slot is available." : ""
      new_patient_addon = is_new ?
        "\n\nA reminder that we do not claim directly from medical aid. Patients pay at the practice and can then claim back using the statement we provide.\n\nPlease arrive 10 minutes early so we can complete your patient file." : ""

      <<~MSG.strip
        Your appointment is booked for #{day_name}, #{date_str} at #{time_str}.#{after_hours_notice}

        #{PRACTICE_ADDRESS}
        Google Maps: #{PRACTICE_MAP_LINK}

        Directions: #{PRACTICE_DIRECTIONS}#{new_patient_addon}

        If you need to change anything, just reply here.
      MSG
    end

    template_service&.send_text(patient.phone, body)
  end

  def time_greeting
    hour = Time.current.hour
    if hour < 12
      "Good morning"
    elsif hour < 17
      "Good afternoon"
    else
      "Good evening"
    end
  end

  def send_reschedule_template(patient, appointment)
    template_service&.send_reschedule(patient, appointment)
  rescue WhatsappTemplateService::Error => e
    Rails.logger.warn("[WhatsApp] Template send failed: #{e.message}")
  end

  def send_cancellation_template(patient, appointment)
    template_service&.send_cancellation(patient, appointment)
  rescue WhatsappTemplateService::Error => e
    Rails.logger.warn("[WhatsApp] Template send failed: #{e.message}")
  end

  def send_confirmation_email(appointment)
    AppointmentMailer.confirmation(appointment).deliver_later
  rescue StandardError => e
    Rails.logger.warn("[WhatsApp] Confirmation email failed: #{e.message}")
  end

  def send_confirmation_sms(appointment)
    SmsService.send_confirmation(appointment)
  rescue StandardError => e
    Rails.logger.warn("[WhatsApp] Confirmation SMS failed: #{e.message}")
  end

  # Multi-channel staff alert when the AI flags a conversation for human
  # follow-up. Channels are configured in practice_config.yml under
  # reception_takeover.notify_channels — default is [sms, email].
  # WhatsApp template channel is best-effort: succeeds when the production
  # sender + flagged-alert template are approved (env var WHATSAPP_TPL_FLAGGED_ALERT
  # set), silently no-ops otherwise so SMS/email always lands.
  def send_flagged_alert(patient, reason)
    channels = Array(PracticeConfig.reception_takeover[:notify_channels])

    # Channel 1 — WhatsApp template (best-effort; deferred until approved)
    begin
      template_service&.send_flagged_alert(patient, reason)
    rescue WhatsappTemplateService::Error => e
      Rails.logger.info("[StaffAlert] WhatsApp template skipped: #{e.message}")
    end

    # Channel 2 — SMS to Paul's emergency_admin_phone (always-on fallback)
    if channels.include?("sms") || channels.include?(:sms)
      SmsService.send_flagged_alert(
        patient_name:  patient.full_name,
        patient_phone: patient.phone,
        reason:        reason
      )
    end

    # Channel 3 — Email to practice info inbox
    if channels.include?("email") || channels.include?(:email)
      begin
        StaffAlertMailer.flagged(
          patient_name:  patient.full_name,
          patient_phone: patient.phone,
          reason:        reason,
          conversation_url: conversation_dashboard_url(patient)
        ).deliver_later
      rescue StandardError => e
        Rails.logger.warn("[StaffAlert] Email failed: #{e.message}")
      end
    end
  end

  # Path B: during business hours, AI is off and reception handles the
  # dashboard. Send a lightweight SMS so reception knows there's a new
  # inbound message to deal with. Email is intentionally NOT used here —
  # they'll see plenty of these and email would be noise. WhatsApp template
  # to the main line is the longer-term plan once approved.
  def send_business_hours_inbound_alert(patient, conversation, message)
    return unless PracticeConfig.report_to_main_line?

    SmsService.send_flagged_alert(
      patient_name:  patient.full_name,
      patient_phone: patient.phone,
      reason:        "New WhatsApp inbound during business hours: #{message.to_s.truncate(80)}"
    )
  rescue StandardError => e
    Rails.logger.warn("[BusinessHoursAlert] Failed: #{e.message}")
  end

  # Path B: after the AI has acted on an after-hours message (booked an
  # appointment, flagged for review, handled an emergency), summarise the
  # event to the main WhatsApp line so reception sees what happened
  # without logging into the dashboard. Best-effort — failure here does
  # not block the patient interaction.
  def report_to_main_line(event_type, patient:, summary:)
    return unless PracticeConfig.report_to_main_line?
    return if PracticeConfig.main_whatsapp.blank?

    # Always send via SMS to emergency_admin_phone — reliable + works today.
    # WhatsApp template to main_whatsapp added once template + sender approved.
    SmsService.send_flagged_alert(
      patient_name:  patient.full_name,
      patient_phone: patient.phone,
      reason:        "[#{event_type}] #{summary}"
    )
  rescue StandardError => e
    Rails.logger.warn("[MainLineReport] Failed: #{e.message}")
  end

  # Best-effort: build the dashboard URL for the patient's most recent
  # active WhatsApp conversation, or nil if none.
  def conversation_dashboard_url(patient)
    convo = patient.conversations.where(channel: "whatsapp", status: "active").order(updated_at: :desc).first
    return nil unless convo

    base = ENV.fetch("APP_BASE_URL", "https://le-roux-production.up.railway.app").delete_suffix("/")
    "#{base}/conversations/#{convo.id}"
  rescue StandardError
    nil
  end

  # --- Helpers ---

  # Updates the patient's first/last name if they still have the
  # placeholder "WhatsApp Patient" name and the AI extracted a real
  # name from the conversation. This means the patient record,
  # appointments list, and dashboard all show the actual name
  # instead of the generic placeholder.
  def update_patient_name(patient, full_name)
    return unless patient.auto_created_placeholder_profile? ||
                  (patient.first_name == "WhatsApp" && patient.last_name == "Patient")

    parts = full_name.to_s.strip.split(/\s+/, 2)
    return if parts.empty?

    first = parts[0]
    last  = parts[1] || patient.last_name

    patient.update(first_name: first, last_name: last)
    Rails.logger.info("[WhatsApp] Updated patient name: #{patient.phone} → #{first} #{last}")
  rescue StandardError => e
    Rails.logger.warn("[WhatsApp] Failed to update patient name: #{e.message}")
  end

  def duration_for_treatment(treatment)
    PracticeConfig.duration_for(treatment).minutes
  end

  def normalize_phone(phone)
    phone.gsub(/\s+/, "").then { |p| p.start_with?("+") ? p : "+#{p}" }
  end

  # True when the current moment falls inside the practice's working
  # hours per DoctorSchedule. Used by build_local_result to decide
  # whether the urgent fast path applies (after-hours only) or whether
  # the AI should handle the message and propose a real slot.
  def currently_within_working_hours?
    schedule = DoctorSchedule.for_day(Time.current.wday)
    return false unless schedule
    schedule.working?(Time.current)
  rescue StandardError
    false
  end

  def extract_cancellation_reason(result)
    # Try to infer reason from the conversation context
    message = result[:response]&.downcase || ""
    if message.include?("cost") || message.include?("expensive") || message.include?("price")
      "cost"
    elsif message.include?("fear") || message.include?("scared") || message.include?("nervous")
      "fear"
    elsif message.include?("time") || message.include?("busy") || message.include?("schedule")
      "timing"
    elsif message.include?("transport") || message.include?("far") || message.include?("travel")
      "transport"
    else
      "other"
    end
  end

  FALLBACK_BUSY = {
    "en" => "I'm sorry, our system is a bit busy right now. Please send your preferred day and time, and our team will follow up as soon as possible.",
    "af" => "Jammer, ons stelsel is tans effens besig. Stuur asseblief jou voorkeur dag en tyd, en ons span sal so gou moontlik opvolg."
  }.freeze
  # Used when the AI returns an uncertain/out-of-scope answer. We flag the
  # conversation for staff review, notify internal channel, then swap the
  # patient-facing message to this fallback so the patient knows a human
  # will follow up rather than being left with a vague AI answer.
  STAFF_REVIEW_FALLBACK = {
    "en" => "Thanks for your message! 😊 I'm an AI assistant, so I can help with *bookings* and most general questions.\n\n" \
            "I'll hand this specific one over to our team — someone from the practice will come back to you personally as soon as possible.\n\n" \
            "In the meantime, is there anything I can help you book? (Check-ups, cosmetic consultations, whitening, fillings, emergencies)",
    "af" => "Baie dankie vir jou boodskap! 😊 Ek is 'n KI-assistent, so ek kan help met *besprekings* en algemene vrae.\n\n" \
            "Vir hierdie spesifieke een sal ek dit aan ons span oorhandig — iemand van die praktyk sal so gou moontlik persoonlik by jou terugkom.\n\n" \
            "Intussen, kan ek help om enigiets te bespreek? (Ondersoeke, kosmetiese konsultasies, bleiking, vullings, noodgevalle)"
  }.freeze


  URGENT_FAST_PATH = {
    "en" => "I'm sorry you're dealing with that. We're open *Monday to Friday, 8am–5pm* and we don't have dentists on duty outside those hours. Please share your name, contact number and a short description — we'll prioritise your case and book you into the very first available slot.",
    "af" => "Ek is jammer om dit te hoor. Ons is oop *Maandag tot Vrydag, 8vm–5nm* en het nie tandartse na-ure werksaam nie. Stuur asseblief jou naam, kontaknommer en 'n kort beskrywing — ons prioritiseer jou saak en bespreek jou in op die eerste beskikbare tyd."
  }.freeze

  def build_fallback_result(message:, conversation:)
    # First try urgent (always immediate)
    result = build_local_result(message: message, conversation: conversation)
    return result if result

    lang = conversation&.language || "en"
    msg_lower = message.downcase

    if msg_lower.match?(/\b(hours?|open|closed|time|schedule|ure|oopmaak|tyd)\b/)
      return {
        response: AiService.dynamic_hours,
        intent: "faq",
        entities: {}
      }
    end

    if msg_lower.match?(/\b(price|cost|how much|consultation|cleaning|prys|koste|hoeveel)\b/)
      return {
        response: "Consultation: #{AiService::PRICING['consultation']} | Cleaning: #{AiService::PRICING['cleaning']}",
        intent: "faq",
        entities: {}
      }
    end

    {
      response: FALLBACK_BUSY[lang] || FALLBACK_BUSY["en"],
      intent: "book",
      entities: {}
    }
  end

  def build_local_result(message:, conversation:)
    # Only use fast path for urgent/emergency (always immediate)
    # Don't use for book/reschedule/cancel (need multi-turn with AI)
    lang = conversation&.language || "en"

    # Urgent fast path: per Paul's v2 emergency policy (PRACTICE_CONFIG_DRAFT §9),
    # the AI MUST always try to book the earliest available slot for emergency
    # patients. The canned URGENT_FAST_PATH text only collects contact details
    # without offering a real slot, so we reserve it for after-hours where no
    # dentist is on duty. During working hours we fall through to the AI so it
    # can read availability_context_block and propose a real slot.
    urgent_match = message.downcase.match?(/\b(pain|urgent|emergency|swollen|bleeding|pyn|noodgeval|geswel|bloeding)\b/)
    if urgent_match && !currently_within_working_hours?
      return {
        response: URGENT_FAST_PATH[lang] || URGENT_FAST_PATH["en"],
        intent: "urgent",
        entities: {}
      }
    end
    # Teeth-whitening: first mention deterministically returns the full info
    # (price, 90 min duration, R2,000 deposit, banking details). Subsequent
    # messages in the same conversation fall through to the AI so follow-up
    # booking questions can be handled conversationally.
    if message.downcase.match?(/\b(teeth whitening|whitening|bleach(ing)?|biolase|tandebleiking|bleiking|tand-bleiking|bleik)\b/) && !whitening_already_sent?(conversation)
      return {
        response: WHITENING_INFO[lang] || WHITENING_INFO["en"],
        intent: "whitening_info",
        entities: {}
      }
    end

    # For other intents, let Claude handle multi-turn conversation
    nil
  end

  def persist_exchange(conversation, user_message, assistant_message)
    conversation.add_messages([
      { role: "user", content: user_message },
      { role: "assistant", content: assistant_message }
    ])
  end

  # --- Language Detection ---

  # Common Afrikaans words and patterns for fast detection.
  # We check against these before falling back to a default of English.
  AFRIKAANS_MARKERS = %w[
    hallo goeie môre middag aand oggend
    ek jy hy sy ons julle hulle
    het kan sal wil moet
    graag asseblief dankie baie seker
    dokter afspraak bespreek tyd
    wanneer hoeveel kos dit maak besig vandag
    vanaand gister laasweek volgende
    maandag dinsdag woensdag donderdag vrydag
    januarie februarie maart april mei junie julie augustus
    september oktober november desember
    ja nee reg beter nie ook
    naam sê praat
    pyn tand mond mondhigiëne
    nuwe pasiënt bestaande
    betaling mediesefonds kontant
    adres rigting parkering
    totsiens groete
    hierdie daai wat waar waarom
  ].freeze

  # Detect language from the message text and persist on the conversation and patient.
  # Only runs detection if the conversation doesn't already have a language set,
  # OR if the user clearly switches language mid-conversation.
  # Also keeps patient.preferred_language in sync for cross-conversation memory.
  def detect_and_persist_language(conversation, message)
    detected = detect_language(message)
    patient = conversation.patient

    if conversation.language.blank?
      conversation.update_column(:language, detected)
      Rails.logger.info("[WhatsApp] Language detected: #{detected} (first message)")
    elsif detected != conversation.language && strong_language_signal?(message, detected)
      conversation.update_column(:language, detected)
      Rails.logger.info("[WhatsApp] Language switched to: #{detected}")
    end

    # Persist preferred language on the patient record if it's changed or unset.
    # This gives us cross-conversation language memory.
    current_lang = conversation.language
    if patient.preferred_language != current_lang
      patient.update_column(:preferred_language, current_lang)
    end
  rescue StandardError => e
    Rails.logger.warn("[WhatsApp] detect_and_persist_language failed: #{e.message}")
  end

  # Simple heuristic language detection: count Afrikaans marker words.
  # Returns "af" or "en".
  def detect_language(message)
    words = message.downcase.gsub(/[^\w\s']/, "").split
    af_count = words.count { |w| AFRIKAANS_MARKERS.include?(w) }

    # If ≥2 Afrikaans markers or ≥30% of words are Afrikaans markers, classify as Afrikaans
    if af_count >= 2 || (words.length > 0 && af_count.to_f / words.length >= 0.3)
      "af"
    else
      "en"
    end
  end

  # Returns true if the message has a strong enough signal to justify switching
  # the conversation language (avoids flipping on borrowed words).
  def strong_language_signal?(message, detected_lang)
    words = message.downcase.gsub(/[^\w\s']/, "").split
    return false if words.length < 2

    if detected_lang == "af"
      af_count = words.count { |w| AFRIKAANS_MARKERS.include?(w) }
      af_count >= 3
    else
      # Switching to English: no Afrikaans markers at all
      af_count = words.count { |w| AFRIKAANS_MARKERS.include?(w) }
      af_count == 0 && words.length >= 3
    end
  end

  # --- Media Download ---

  # Download all media attachments from Twilio, returning an array of
  # { content_type:, data: (base64) } hashes ready for the Claude API.
  # Individual failures are swallowed — the message still processes.
  def download_media_attachments(attachments)
    return [] if attachments.blank?

    attachments.filter_map do |attachment|
      download_media(attachment[:url], attachment[:content_type])
    rescue StandardError => e
      Rails.logger.warn("[WhatsApp] Media download failed (#{attachment[:url]}): #{e.message}")
      nil
    end
  end

  # Download a single Twilio media URL using Basic Auth credentials.
  # Returns { content_type:, data: (base64 string) } or raises on failure.
  def download_media(url, content_type)
    account_sid = ENV.fetch("TWILIO_ACCOUNT_SID")
    auth_token  = ENV.fetch("TWILIO_AUTH_TOKEN")

    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 30

    request = Net::HTTP::Get.new(uri.request_uri)
    request.basic_auth(account_sid, auth_token)

    response = http.request(request)
    raise Error, "HTTP #{response.code} downloading media from Twilio" unless response.is_a?(Net::HTTPSuccess)

    { content_type: content_type, data: Base64.strict_encode64(response.body) }
  end

  # Find the next working day (up to 14 days ahead) where the requested
  # time string ("14:00") is available for `duration` minutes without
  # conflicting with existing appointments.
  def next_available_date_for_time(time_str, duration = PracticeConfig.default_appointment_duration_minutes.minutes)
    date = Date.current
    14.times do
      date = date.next_day
      schedule = DoctorSchedule.for_day(date.wday)
      next unless schedule

      candidate_start = Time.zone.parse("#{date} #{time_str}")
      candidate_end   = candidate_start + duration

      next unless candidate_start > Time.current
      next unless schedule.working?(candidate_start) && schedule.working?(candidate_end - 1.minute)
      next if slot_conflicts_locally?(candidate_start, candidate_end)

      return date
    end
    nil
  rescue StandardError => e
    Rails.logger.warn("[WhatsApp] next_available_date_for_time failed: #{e.message}")
    nil
  end

  def ai_service
    @ai ||= AiService.new
  end

  def template_service
    @templates ||= begin
      WhatsappTemplateService.new(from_number: @inbound_to)
    rescue StandardError
      # Template service may fail if Twilio creds aren't set (dev/test)
      nil
    end
  end
end

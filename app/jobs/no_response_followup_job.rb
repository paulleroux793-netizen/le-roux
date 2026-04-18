class NoResponseFollowUpJob < ApplicationJob
  queue_as :default

  # How long after the last bot message before each follow-up fires.
  FIRST_FOLLOWUP_AFTER  = 10.minutes
  SECOND_FOLLOWUP_AFTER = 90.minutes

  # Look back no further than this — stale conversations are ignored.
  LOOKBACK_WINDOW = 3.hours

  def perform
    now = Time.current

    Conversation
      .where(channel: "whatsapp", status: "active")
      .where("updated_at > ?", now - LOOKBACK_WINDOW)
      .where("follow_up_count < 2")
      .includes(:patient)
      .find_each do |conversation|
        process_conversation(conversation, now)
      end
  end

  private

  def process_conversation(conversation, now)
    messages = Array(conversation.messages)
    return if messages.empty?

    last_msg = messages.last
    # Only follow up when the most recent message is from the bot, not the patient
    return if last_msg["role"] == "user"

    last_at = begin
      Time.zone.parse(last_msg["timestamp"].to_s)
    rescue ArgumentError, TypeError
      conversation.updated_at
    end

    idle_secs = (now - last_at).to_i

    if conversation.follow_up_count == 0 && idle_secs >= FIRST_FOLLOWUP_AFTER.to_i
      send_followup(conversation, :first)
    elsif conversation.follow_up_count == 1 && idle_secs >= SECOND_FOLLOWUP_AFTER.to_i
      send_followup(conversation, :second)
    end
  rescue StandardError => e
    Rails.logger.error("[NoResponseFollowUp] Error processing conversation #{conversation.id}: #{e.message}")
  end

  def send_followup(conversation, type)
    patient  = conversation.patient
    lang     = conversation.language || "en"
    message  = followup_message(type, lang)

    template_service = WhatsappTemplateService.new
    template_service.send_text(patient.phone, message)

    # Persist follow-up state atomically
    conversation.with_lock do
      conversation.increment!(:follow_up_count)
      conversation.update_column(:follow_up_sent_at, Time.current)
      conversation.update_column(:status, "stale") if type == :second
    end

    Rails.logger.info(
      "[NoResponseFollowUp] #{type} follow-up sent to #{patient.phone} " \
      "(conversation #{conversation.id}, idle #{conversation.follow_up_count} follow-ups sent)"
    )
  rescue StandardError => e
    Rails.logger.error(
      "[NoResponseFollowUp] Failed to send #{type} follow-up to conversation " \
      "#{conversation.id}: #{e.message}"
    )
  end

  def followup_message(type, lang)
    if type == :first
      lang == "af" ?
        "Hallo! Ek wil net uitcheck — was jy in staat om 'n tyd te vind wat werk, of kan ek jou help om 'n afspraak te bespreek? 😊" :
        "Hi there! Just checking in — were you able to find a time that works, or can I help you book an appointment? 😊"
    else
      lang == "af" ?
        "Ons is nog hier wanneer jy gereed is! Stuur gerus 'n boodskap om 'n afspraak te bespreek. — Dr Chalita & span" :
        "We're still here whenever you're ready! Feel free to message us to book an appointment. — Dr Chalita & team"
    end
  end
end

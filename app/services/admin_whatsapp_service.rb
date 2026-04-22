class AdminWhatsappService
  ADMIN_NUMBER = ENV.fetch("ADMIN_WHATSAPP_NUMBER", "+27714475022")

  HELP_TEXT = <<~HELP.strip
    *Dr Le Roux Admin Commands*

    Send any instruction to add it to the AI's behaviour. Examples:
    • "Always ask patients for their medical aid number"
    • "Do not offer Saturday appointments"
    • "Remind patients to bring a referral letter"

    *Commands:*
    • *show* — view current custom instructions
    • *clear* — remove all custom instructions
    • *help* — show this message
  HELP

  def self.admin?(phone)
    normalize(phone) == normalize(ADMIN_NUMBER)
  end

  def handle(message)
    cmd = message.strip.downcase

    case cmd
    when "help"
      send_reply(HELP_TEXT)
    when "show"
      instructions = settings.admin_instructions.presence
      text = instructions ? "*Current instructions:*\n\n#{instructions}" : "No custom instructions set yet."
      send_reply(text)
    when "clear", "reset"
      settings.update!(admin_instructions: nil)
      send_reply("All custom instructions cleared. The AI is back to default behaviour.")
    else
      append_instruction(message.strip)
    end
  end

  private

  def append_instruction(instruction)
    current = settings.admin_instructions.presence
    updated = [ current, instruction ].compact.join("\n")
    settings.update!(admin_instructions: updated)
    send_reply("Got it, Paul. Instruction saved:\n\n_#{instruction}_\n\nSend *show* to see all active instructions.")
  rescue StandardError => e
    Rails.logger.error("[AdminWhatsapp] Failed to save instruction: #{e.message}")
    send_reply("Sorry, I couldn't save that instruction. Please try again.")
  end

  def send_reply(text)
    WhatsappTemplateService.new.send_text(ADMIN_NUMBER, text)
  rescue StandardError => e
    Rails.logger.error("[AdminWhatsapp] Failed to send reply to admin: #{e.message}")
  end

  def settings
    @settings ||= PracticeSettings.instance
  end

  def self.normalize(phone)
    phone.to_s.gsub(/\D/, "")
  end
end

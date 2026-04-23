class AdminWhatsappService
  ADMIN_NUMBERS = [
    ENV.fetch("ADMIN_WHATSAPP_NUMBER", "+27714475022"),  # Paul Le Roux
    ENV.fetch("ADMIN_WHATSAPP_NUMBER_2", "+27721690521") # Dieumerci
  ].freeze

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
    • *menu* — switch between Admin / Patient Test mode
  HELP

  MODE_SELECTOR_TEXT = <<~MSG.strip
    👋 Hi! What would you like to do?

    *1* — 🔧 Admin Mode _(manage bot instructions)_
    *2* — 🧪 Test as Patient _(chat with the bot as a real patient would)_

    Reply with *1* or *2*.
  MSG

  GREETINGS = %w[hi hello hey hallo howzit morning afternoon evening].freeze

  def self.admin?(phone)
    normalized = normalize(phone)
    ADMIN_NUMBERS.any? { |n| normalize(n) == normalized }
  end

  # Returns true when the admin has switched into patient-test mode.
  # The controller uses this to bypass admin routing.
  def self.admin_in_patient_mode?(phone)
    PracticeSettings.instance.admin_mode_for(phone) == "patient"
  end

  # Returns true for messages that control mode — always handled
  # synchronously regardless of current mode.
  def self.mode_command?(message)
    %w[1 2 menu].include?(message.to_s.strip.downcase)
  end

  def initialize(sender_phone)
    @sender_phone = sender_phone
  end

  def handle(message)
    cmd = message.strip.downcase

    # Mode switching — processed first, always
    case cmd
    when "1"
      set_mode("admin")
      send_reply("✅ *Admin Mode* activated.\n\n#{HELP_TEXT}")
      return
    when "2"
      set_mode("patient")
      send_reply(
        "🧪 *Patient Test Mode* activated.\n\n" \
        "You'll now chat with the bot exactly as a patient would — " \
        "bookings, reminders, and all.\n\n" \
        "Send *menu* at any time to switch back to Admin Mode."
      )
      return
    when "menu"
      send_reply(MODE_SELECTOR_TEXT)
      return
    end

    # Greetings → show mode selector so admin always sees the options first
    if GREETINGS.include?(cmd)
      send_reply(MODE_SELECTOR_TEXT)
      return
    end

    # Guard: if somehow handle() is called while in patient mode, redirect
    if current_mode == "patient"
      send_reply("You're in Patient Test Mode. Send *menu* to switch back to Admin Mode.")
      return
    end

    # Admin-mode commands
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

  def current_mode
    @current_mode ||= settings.admin_mode_for(@sender_phone)
  end

  def set_mode(mode)
    settings.set_admin_mode(@sender_phone, mode)
    @current_mode = mode
  end

  def append_instruction(instruction)
    current = settings.admin_instructions.presence
    updated = [ current, instruction ].compact.join("\n")
    settings.update!(admin_instructions: updated)
    send_reply("Got it. Instruction saved:\n\n_#{instruction}_\n\nSend *show* to see all active instructions.")
  rescue StandardError => e
    Rails.logger.error("[AdminWhatsapp] Failed to save instruction: #{e.message}")
    send_reply("Sorry, I couldn't save that instruction. Please try again.")
  end

  def send_reply(text)
    WhatsappTemplateService.new.send_text(@sender_phone, text)
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

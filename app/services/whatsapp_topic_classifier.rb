class WhatsappTopicClassifier
  # Phase 10 — deterministic keyword-based topic classifier for
  # historical WhatsApp imports.
  #
  # Given the raw text of a conversation (all messages joined) this
  # returns a short human label for the list view ("Appointment
  # booking", "Billing question", etc.). We deliberately avoid an
  # LLM call per imported chat — for thousands of historical
  # threads that gets expensive and slow, and a keyword rubric is
  # accurate enough for the receptionist's "what was this about?"
  # glance. The classifier can be swapped for a smarter one later
  # without changing the schema (topic is a plain string column).
  #
  # Rules are ordered — first match wins, so put more specific
  # intents before generic ones.
  RULES = [
    { topic: "Appointment cancellation",
      patterns: [/\bcancel(l?ed|ling|lation)?\b/i, /can'?t (come|make)/i, /won'?t be able to/i] },

    { topic: "Appointment rescheduling",
      patterns: [/\breschedul/i, /move (my |the )?appointment/i, /change (my )?(appointment|booking|time)/i, /different (day|time|date)/i] },

    { topic: "Appointment confirmation",
      patterns: [/\bconfirm/i, /\bstill on\b/i, /see you (then|tomorrow|today)/i] },

    { topic: "Appointment booking",
      patterns: [/\bbook(ing)?\b/i, /\bappointment\b/i, /make an appointment/i, /set up (an?|my) (visit|appointment)/i, /\bavailability\b/i, /available (slot|time|day)/i] },

    { topic: "Prescription / medication",
      patterns: [/\bprescription\b/i, /\brefill\b/i, /\bmedication\b/i, /\bmedicine\b/i, /\bantibiotic/i, /\bpainkiller/i] },

    { topic: "Billing / payment",
      patterns: [/\b(invoice|bill|billing|payment|pay|paid|quote|cost|price|fee|charge|medical aid|insurance|claim)\b/i] },

    { topic: "Dental emergency",
      patterns: [/\bemergenc/i, /\burgent/i, /severe pain/i, /\bbleeding\b/i, /\bswollen\b/i, /\bbroken tooth\b/i, /knocked out/i] },

    { topic: "Toothache / pain",
      patterns: [/\btoothache\b/i, /\btooth (is )?(hurting|sore|painful)/i, /\bpain\b/i, /\bache\b/i, /\bsore\b/i] },

    { topic: "Cleaning / check-up",
      patterns: [/\bcleaning\b/i, /\bcheck[- ]?up\b/i, /\bhygien/i, /\bscale (and|&) polish\b/i] },

    { topic: "Follow-up",
      patterns: [/\bfollow[- ]?up\b/i, /\bafter (my|the) (visit|appointment|procedure)/i, /\bpost[- ]?op/i] },

    { topic: "Directions / location",
      patterns: [/\b(address|directions?|location|parking|how do i get|where are you)\b/i] },

    { topic: "Opening hours",
      patterns: [/\b(open|opening hours?|closed|closing time|what time do you)\b/i]   }
  ].freeze

  DEFAULT_TOPIC = "General enquiry".freeze

  def self.classify(text)
    return DEFAULT_TOPIC if text.blank?

    haystack = text.to_s
    RULES.each do |rule|
      return rule[:topic] if rule[:patterns].any? { |pat| haystack.match?(pat) }
    end
    DEFAULT_TOPIC
  end
end

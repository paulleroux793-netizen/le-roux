# Outbound compliance filter for every patient-facing WhatsApp message.
#
# The AI brain (AiService) generates the reply text; this class is the LAST
# line of defence before that text is sent to a patient. It scans for the
# banned phrasing defined in the practice brand file
# (`_shared/dr-chalita-practice-brand.md` §2 "The 11 hard rules" and §6
# "Always-banned phrases") and the project memory rules
# (`00-memory/rules/banned-phrases.md`, `approved-framings.md`).
#
# Design principles (deliberately conservative — this runs on a LIVE line):
#   * TARGETED replacement only. We swap a specific banned phrase for an
#     approved alternative; we do NOT delete or rewrite whole messages. A
#     false positive that mangles a booking confirmation is worse than a
#     marginal phrase slipping through (the AI prompt already steers away
#     from banned wording — this is belt-and-braces).
#   * Where no safe inline replacement exists, we strip just the offending
#     clause (up to the nearest sentence boundary) rather than the message.
#   * Every hit is logged with Rails.logger.warn("[ComplianceFilter] ...")
#     and surfaced in the returned :flagged list so the wiring layer can
#     escalate / record it.
#   * Regexes are case-insensitive and word-boundary-aware to avoid false
#     hits (e.g. "Pretoria" must not match inside another token).
#
# Usage:
#   result = ComplianceFilter.scrub(text)
#   result[:text]    # => cleaned text (== input when nothing matched)
#   result[:flagged] # => array of rule-key symbols that fired, e.g.
#                    #    [:after_hours, :superlatives]
#
# Rule keys (stable identifiers; mirror the brand-file rule numbers where
# applicable):
#   :after_hours        — Rule 3: 24-hour / weekend / "see you today" promises
#   :medical_aid_direct — Rule 4: direct medical-aid billing claims
#   :medication_dosing  — Rule 5: specific medication dosing instructions
#   :superlatives       — Rule 6: absolute claims / superlatives / guarantees
#   :geo_pretoria       — Rule 8: Pretoria (practice is in Roodepoort)
class ComplianceFilter
  # Each entry: a regex (case-insensitive, anchored on word boundaries where
  # sensible) and the replacement string. Replacements are drawn from the
  # brand file's "Always-approved replacements" (§6) and §2 approved framings.
  #
  # Order matters: more specific patterns are listed before broader ones so a
  # specific approved replacement wins over a generic strip.

  # --- Rule 3: after-hours / 24-hour / weekend / "see you today" ---
  AFTER_HOURS_RULES = [
    # "we'll see you today" / "see you today" / "we'll fit you in today" →
    # soften to the approved "as quickly as possible once you arrive" framing.
    [/\bwe['’]?ll\s+see\s+you\s+today\b/i,            "we'll aim to see you as quickly as possible once you arrive"],
    [/\bsee\s+you\s+today\b/i,                        "we'll aim to see you as quickly as possible once you arrive"],
    [/\bwe['’]?ll\s+fit\s+you\s+in\s+today\b/i,       "we'll aim to see you as quickly as possible once you arrive"],
    [/\bwe['’]?ll\s+have\s+a\s+chair\s+ready\b/i,     "we'll be ready for your arrival"],
    [/\bwe['’]?ll\s+come\s+in\b/i,                    "we'll see you during our regular daytime hours"],
    # 24-hour / 24/7 AVAILABILITY framing → state real hours. Narrow on purpose:
    # must be an availability/service claim, NOT incidental timing like "a
    # reminder 24 hours before your appointment" or "we'll confirm within 24 hours".
    [%r{\b24[\s/-]?7\b}i,                             "Monday to Friday, 8am–5pm"],
    [%r{\bopen\s+(?:24|twenty[-\s]?four)[\s/-]?hours?\b}i, "open Monday to Friday, 8am–5pm"],
    [%r{\b(?:24|twenty[-\s]?four)[\s/-]?hours?\s+(?:a\s+day|service|care|availability|emergenc(?:y|ies)|cover|clinic|practice|dental|support|open|line|hotline)\b}i,
                                                       "Monday to Friday, 8am–5pm"],
    [/\baround[-\s]the[-\s]clock\b/i,                 "during our regular daytime hours"],
    # weekend availability claims → state we're closed weekends.
    [/\bweekend\s+(?:cover|trauma|availability|appointments?|emergenc(?:y|ies))\b/i,
                                                       "appointments Monday to Friday (we're closed on weekends)"],
    [/\b(?:open|available)\s+(?:on\s+)?(?:weekends?|saturdays?|sundays?)\b/i,
                                                       "open Monday to Friday (we're closed on weekends)"],
    # "see you this/on the weekend" booking promises → state weekend closure.
    # Narrow: requires "see you ... weekend", so it won't touch "have a great weekend".
    [/\bsee\s+you\s+(?:this|on|over)(?:\s+the)?\s+weekend\b/i,
                                                       "see you on the next working day (we're closed on weekends)"],
    [/\b(?:available|come\s+in|book\s+you)\s+(?:this|on|over)(?:\s+the)?\s+(?:weekend|saturday|sunday)\b/i,
                                                       "see you on the next working day (we're closed on weekends)"],
    # after-hours protocol / redirect promises.
    [/\bafter[-\s]hours?\s+(?:protocol|contact|referral(?:\s+pathway)?|cover|service|appointments?)\b/i,
                                                       "care during our regular daytime hours"]
  ].freeze

  # --- Rule 4: direct medical-aid billing claims ---
  MEDICAL_AID_RULES = [
    [/\bwe\s+(?:bill|claim)\s+(?:your\s+)?medical\s+(?:aid|scheme)\s+(?:for\s+you|directly|on\s+your\s+behalf)\b/i,
                                                       "we provide a detailed statement which you submit to your medical scheme for reimbursement"],
    [/\bwe\s+submit\s+(?:your\s+)?(?:claims?|the\s+claim)\s+(?:for\s+you|on\s+your\s+behalf|directly)?\b/i,
                                                       "we provide a statement which you submit to your scheme yourself"],
    [/\bwe\s+deal\s+with\s+your\s+(?:medical\s+aid|scheme)\s+directly\b/i,
                                                       "we provide a statement which you submit to your scheme yourself"],
    [/\b(?:direct|directly)\s+bill(?:ing|s)?\s+(?:to\s+)?(?:your\s+)?medical\s+(?:aid|scheme)\b/i,
                                                       "a statement you submit to your medical scheme yourself"]
  ].freeze

  # --- Rule 5: specific medication dosing ---
  # We do NOT try to identify the drug — any explicit dose/frequency in a
  # patient-facing message is replaced with the approved deferral framing.
  # Matches e.g. "400 mg every 6 hours", "two tablets every 4 hrs",
  # "5 ml twice daily".
  MEDICATION_DOSING_RULES = [
    [/\b\d+(?:\.\d+)?\s?(?:mg|milligrams?|ml|millilitres?|milliliters?)\b(?:[^.?!]*?\b(?:every|per|each|times?|daily|hourly|hours?|hrs?)\b[^.?!]*)?/i,
                                                       "the dose shown on the medication packaging (ask your pharmacist if you're unsure)"],
    [/\b(?:one|two|three|four|1|2|3|4)\s+(?:tablets?|capsules?|pills?)\s+(?:every|per|each)\s+\d+\s*(?:hours?|hrs?|hourly)\b/i,
                                                       "the dose shown on the medication packaging (ask your pharmacist if you're unsure)"]
  ].freeze

  # --- Rule 6: absolute claims / superlatives / guarantees ---
  SUPERLATIVE_RULES = [
    [/\bpainless\b/i,                                  "comfortable"],
    [/\bguarantee(?:d|s)?\b/i,                          "aim for"],
    [/\bthe\s+best\b/i,                                "a trusted"],
    # "best/finest/top/leading dentist/dental practice/clinic" → neutral framing.
    # Narrow: requires a practice noun, so it won't touch "best regards"/"works best".
    [/\b(?:the\s+)?(?:best|finest|top|leading|greatest|premier)\s+(?:dentist|dental(?:\s+(?:practice|care|clinic))?|practice|clinic)\b/i,
                                                       "a trusted dental practice"],
    [/#\s?1\b/i,                                        "a trusted"],
    [/\b(?:the\s+)?number\s+one\b/i,                   "a trusted"],
    [/\bcheapest\b/i,                                  "well-priced"],
    # "the only practice/dentist/clinic in…" is a banned exclusivity claim, but
    # "the only slot/time left" is legitimate booking language — use a lookahead
    # so we only neutralise the exclusivity claim.
    [/\bthe\s+only\b(?=\s+(?:practice|dentist|dental|clinic|surgery|choice|option\s+for))/i, "a"],
    [/\b(?:south\s+africa['’]?s|gauteng['’]?s)\s+(?:leading|#?\s?1|number\s+one|top|best)\b/i,
                                                       "a trusted"],
    [/\bworld[-\s]class\b/i,                           "quality"]
  ].freeze

  # --- Rule 8: geo — practice is in Roodepoort, never Pretoria ---
  # Word-boundary anchored so it won't match inside another token. We only
  # strip the standalone city reference; we don't try to rewrite geography.
  GEO_RULES = [
    [/\bin\s+Pretoria\b/i,                             "in Roodepoort"],
    [/\bPretoria\b/i,                                  "Roodepoort"]
  ].freeze

  RULE_GROUPS = {
    after_hours:        AFTER_HOURS_RULES,
    medical_aid_direct: MEDICAL_AID_RULES,
    medication_dosing:  MEDICATION_DOSING_RULES,
    superlatives:       SUPERLATIVE_RULES,
    geo_pretoria:       GEO_RULES
  }.freeze

  # Scrub an outbound message. Returns { text:, flagged: [rule_key, ...] }.
  # Never raises — on any unexpected error it returns the original text
  # unflagged so a filter bug can never block a patient reply.
  def self.scrub(text)
    return { text: text, flagged: [] } if text.blank?

    cleaned = text.to_s
    flagged = []

    RULE_GROUPS.each do |rule_key, rules|
      rules.each do |pattern, replacement|
        next unless pattern.match?(cleaned)
        # Don't "correct" an after-hours/24-hour/weekend mention the AI is
        # NEGATING ("we don't have a 24-hour line", "we're not open on weekends").
        # That's already compliant — rewriting it produces garble.
        next if rule_key == :after_hours && negated?(cleaned, pattern)

        flagged << rule_key
        cleaned = cleaned.gsub(pattern, replacement)
      end
    end

    flagged.uniq!

    if flagged.any?
      cleaned = tidy_whitespace(cleaned)
      Rails.logger.warn(
        "[ComplianceFilter] Scrubbed outbound message. rules=#{flagged.inspect} " \
        "original=#{text.to_s[0..200].inspect}"
      )
    end

    { text: cleaned, flagged: flagged }
  rescue StandardError => e
    Rails.logger.error("[ComplianceFilter] scrub failed, passing original through: #{e.class}: #{e.message}")
    { text: text, flagged: [] }
  end

  # True when the banned phrase is being negated just before the match (so the
  # AI is correctly saying we DON'T offer it). Looks ~40 chars back for a
  # negation cue. Prevents rewriting "we don't have a 24-hour line" into garble.
  def self.negated?(text, pattern)
    m = pattern.match(text)
    return false unless m

    preceding = text[0...m.begin(0)].to_s.downcase
    window = preceding[-40..] || preceding
    window.match?(/\b(?:no|not|n't|don't|do not|isn't|aren't|won't|never|unfortunately|without)\b/) ||
      window.include?("n't ")
  end
  private_class_method :negated?

  # Collapse any double spaces / orphaned punctuation a replacement may have
  # introduced, without disturbing intentional newlines or markdown.
  def self.tidy_whitespace(text)
    text.gsub(/[ \t]{2,}/, " ").gsub(/\s+([.,!?])/, '\1')
  end
  private_class_method :tidy_whitespace
end

# Extracts dental findings from a chair-side transcript and maps them to SADA procedure codes.
#
# Two backends:
#   - PRODUCTION (when ANTHROPIC_API_KEY is set): Claude reads the transcript
#     AND the practice's actual procedure-code catalogue (so it can only
#     return codes that exist), and emits structured findings.
#   - FALLBACK: deterministic keyword/tooth-number parser. Never invents
#     codes that aren't in the catalogue (Audit fix #21).
#
# Either way the output is a list of PROPOSED findings the dentist reviews;
# nothing auto-applies. The DailyReconciliationService uses these to
# compute "Ivory predicted Rxxx" estimate values for the daily diff.
#
# Output shape (Array<Hash>):
#   [
#     { "tooth" => "36", "code" => "8341", "needs_code" => false,
#       "note" => "...", "confidence" => "high" },
#     ...
#   ]
class ScribeDraftService
  KEYWORD_CODES = {
    /extract|extraction|remove\s+tooth/i => "8201",
    /fill|filling|restor|caries|decay/i  => "8341",
    /crown/i                             => "8443",
    /exam|examination|check/i            => "8101",
    /clean|scal|polish|hygiene|prophy/i  => "8155",
    /bridge/i                            => "8447",
    /root\s+canal|rct|endo/i             => "8367",
    /x-?ray|periapical|bitewing|opg|panoramic/i => "8107",
    /local|anaesthe|anesthe/i            => "8110",
    /whitening|bleach/i                  => "8159"
  }.freeze

  PROMPT_SYSTEM = <<~PROMPT.freeze
    You are a clinical scribe assistant for a private South African dental
    practice (Dr Chalita le Roux Inc). Read a transcript of a single dental
    consultation/procedure and identify each chargeable clinical action the
    dentist mentioned. The output drives a DRAFT estimate the dentist will
    review — never an auto-bill.

    HARD RULES:
    - Output STRICT JSON only, with this exact shape:
      { "findings": [{ "tooth": "36", "code": "8341", "note": "<short>", "confidence": "high|medium|low" }, ...] }
    - "tooth" MUST be FDI two-digit (e.g. "16", "36", "47") or null when the
      action is not tooth-specific (e.g. exam, cleaning, x-ray).
    - "code" MUST be drawn ONLY from the catalogue I'm about to pass you
      below. If a clinical action was mentioned but no code in the catalogue
      maps to it, OMIT it from findings (don't guess).
    - Don't include findings the dentist mentioned but explicitly ruled out
      ("we'll watch this", "no need to do anything").
    - SA English. Rands not dollars.
  PROMPT

  def initialize(transcript)
    @transcript = transcript.to_s
  end

  def extract
    return [] if @transcript.strip.empty?
    if claude_available?
      result = claude_extract
      return result if result.any?
    end
    keyword_extract
  end

  private

  def claude_available?
    ENV["ANTHROPIC_API_KEY"].present? && !ENV["ANTHROPIC_API_KEY"].start_with?("dummy", "harness")
  end

  def claude_extract
    require "anthropic"
    catalogue = ProcedureCode.order(:code).limit(500).map { |p|
      "#{p.code}: #{p.description.to_s.slice(0, 80)}"
    }.join("\n")

    client = Anthropic::Client.new(access_token: ENV["ANTHROPIC_API_KEY"])
    msg = client.messages(parameters: {
      model: ENV.fetch("ANTHROPIC_SUMMARY_MODEL", "claude-haiku-4-5-20251001"),
      max_tokens: 800,
      system: PROMPT_SYSTEM,
      messages: [ {
        role: "user",
        content: "CATALOGUE OF VALID CODES (only choose from these):\n#{catalogue}\n\nTRANSCRIPT:\n#{@transcript}"
      } ]
    })
    content = msg.dig("content", 0, "text") || msg["content"].to_s
    content = content.gsub(/\A```(?:json)?\s*/, "").gsub(/```\s*\z/, "").strip
    parsed = JSON.parse(content)
    Array(parsed["findings"]).map { |f|
      code = f["code"].to_s.strip
      code = nil unless code.present? && ProcedureCode.exists?(code: code)
      {
        "tooth" => f["tooth"].to_s.strip.presence,
        "code"  => code,
        "needs_code" => code.nil?,
        "note"  => f["note"].to_s.strip,
        "confidence" => f["confidence"].to_s.strip.presence || "medium"
      }
    }.uniq { |f| [ f["tooth"], f["code"], f["note"] ] }
  rescue StandardError => e
    Rails.logger.warn("[ScribeDraftService] Claude extract failed (#{e.class}: #{e.message}); falling back to keyword parser")
    []
  end

  def keyword_extract
    findings = []
    @transcript.split(/[.;\n]/).each do |clause|
      teeth = clause.scan(/\b([1-4][1-8])\b/).flatten.uniq
      KEYWORD_CODES.each do |pattern, code|
        next unless clause.match?(pattern)
        resolved = ProcedureCode.exists?(code: code) ? code : nil
        targets = teeth.any? ? teeth : [ nil ]
        targets.each do |t|
          findings << {
            "tooth" => t,
            "code"  => resolved,
            "needs_code" => resolved.nil?,
            "note"  => clause.strip.slice(0, 200),
            "confidence" => "low"
          }
        end
      end
    end
    findings.uniq { |f| [ f["tooth"], f["code"], f["note"] ] }
  end
end

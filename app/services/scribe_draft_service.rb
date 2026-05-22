# Extracts dental findings from a chair-side transcript and maps them to procedure codes.
#
# Two backends:
#   - PRODUCTION: Claude (Anthropic) reads the transcript + tooth chart for high-quality extraction.
#   - FALLBACK (used when no ANTHROPIC_API_KEY / offline): a deterministic keyword+tooth-number parser.
# Either way the output is a list of PROPOSED findings the dentist reviews — never auto-applied.
class ScribeDraftService
  # keyword -> SADA procedure code (only codes that exist in the catalogue are used downstream)
  KEYWORD_CODES = {
    /extract|extraction|remove/i      => "8201",
    /fill|filling|restor|caries|decay/i => "8341",
    /crown/i                          => "8443",
    /exam|examination|check/i         => "8101",
    /clean|scal|polish|hygiene/i      => "8155"
  }.freeze

  def initialize(transcript)
    @transcript = transcript.to_s
  end

  def extract
    return claude_extract if claude_available?
    keyword_extract
  end

  private

  def claude_available?
    ENV["ANTHROPIC_API_KEY"].present? && !ENV["ANTHROPIC_API_KEY"].start_with?("dummy")
  end

  # Placeholder for the production path. Structured so AiService/Anthropic can be plugged in:
  # send transcript + chart, get back [{tooth, action, code, note}]. Falls back on any error.
  def claude_extract
    keyword_extract # TODO: wire Anthropic; until then use the deterministic parser
  rescue StandardError
    keyword_extract
  end

  # Deterministic: find FDI tooth numbers near action keywords.
  # IMPORTANT: only attach a procedure code if it actually exists in the practice catalogue;
  # otherwise leave code nil + needs_code so the dentist selects it during review (never guess a
  # wrong billable code). (Audit fix #21.)
  def keyword_extract
    findings = []
    @transcript.split(/[.;\n]/).each do |clause|
      teeth = clause.scan(/\b([1-4][1-8])\b/).flatten.uniq
      KEYWORD_CODES.each do |pattern, code|
        next unless clause.match?(pattern)
        resolved = ProcedureCode.exists?(code: code) ? code : nil
        targets = teeth.any? ? teeth : [ nil ]
        targets.each do |t|
          findings << { "tooth" => t, "code" => resolved, "needs_code" => resolved.nil?, "note" => clause.strip }
        end
      end
    end
    findings.uniq { |f| [ f["tooth"], f["code"], f["note"] ] }
  end
end

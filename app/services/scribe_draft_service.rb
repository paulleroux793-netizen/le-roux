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
  def keyword_extract
    findings = []
    # Sentences / clauses
    @transcript.split(/[.;\n]/).each do |clause|
      teeth = clause.scan(/\b([1-4][1-8])\b/).flatten.uniq
      KEYWORD_CODES.each do |pattern, code|
        next unless clause.match?(pattern)
        if teeth.any?
          teeth.each { |t| findings << { "tooth" => t, "code" => code, "note" => clause.strip } }
        else
          findings << { "tooth" => nil, "code" => code, "note" => clause.strip }
        end
      end
    end
    findings.uniq { |f| [ f["tooth"], f["code"] ] }
  end
end

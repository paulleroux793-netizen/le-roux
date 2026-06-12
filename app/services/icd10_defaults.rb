# Default ICD-10 diagnosis code per dental procedure, so estimate/invoice lines are
# claim-ready out of the box (SADA: every billed tariff line needs an ICD-10). The
# dentist can override per line. Mapping is SADA/Perplexity-researched (2026-06-11):
#   exam/radiograph/hygiene/infection-control → Z01.2 (dental examination)
#   fillings/crowns/restorations/simple extraction → K02.9 (dental caries, unspecified)
#   root canal / pulp → K04.0 (pulpitis)
#   surgical/impacted extraction → K01.1 (impacted teeth)
#   implant / denture / bridge → K08.4 (partial loss of teeth)
#   cosmetic whitening → Z41.8 (procedure for purposes other than health)
module Icd10Defaults
  FALLBACK = "Z01.2".freeze

  def self.for(procedure_code)
    return nil if procedure_code.nil?
    code = procedure_code.code.to_s
    n    = code[/\A\d+/].to_i
    desc = procedure_code.description.to_s

    return "Z41.8" if desc =~ /bleach|whiten/i                                   # cosmetic whitening
    return "K01.1" if desc =~ /surgical removal|impacted|odontectomy|surgical extraction/i
    return "K08.4" if desc =~ /implant|denture|bridge|pontic|overdenture|abutment/i
    return "K04.0" if desc =~ /root canal|pulp|obturation|endodont/i || (8300..8340).cover?(n)
    return "K02.9" if desc =~ /crown|inlay|onlay|resin|filling|restorat|veneer|core build/i
    return "K02.9" if (8200..8210).cover?(n)                                     # extractions (caries default)
    return "K02.9" if (8350..8599).cover?(n)                                     # restorative range
    return "Z01.2" if (8100..8166).cover?(n)                                     # exam/x-ray/hygiene/infection control/anaesthetic

    case procedure_code.category
    when "restorative", "surgical" then "K02.9"
    when "diagnostic"              then "Z01.2"
    else FALLBACK
    end
  end
end

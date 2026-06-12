# Shared line maths for estimate_lines and invoice_lines.
# VAT treatment: fees are stored VAT-INCLUSIVE (SA convention — see UNCERTAINTIES #17).
# Zero-rated (medical) lines carry no VAT; standard-rated (cosmetic, e.g. whitening) have 15%
# extracted from the inclusive price.
module BillableLine
  extend ActiveSupport::Concern

  STANDARD_VAT_RATE = 0.15

  included do
    before_validation :compute_totals
    before_validation :default_icd10
  end

  # Claim-ready: every billed line needs an ICD-10 (SADA). Auto-fill a sensible default
  # from the procedure when blank; the dentist can override per line.
  def default_icd10
    return unless respond_to?(:icd10_code)
    return if icd10_code.present?
    pc = (respond_to?(:procedure_code) && procedure_code) ||
         (respond_to?(:code) && code.present? ? ProcedureCode.find_by(code: code) : nil)
    self.icd10_code = Icd10Defaults.for(pc) if pc
  end

  def compute_totals
    self.quantity = 1 if quantity.to_i < 1
    self.line_total_cents = quantity.to_i * unit_fee_cents.to_i
    self.vat_cents =
      if vat_treatment == "standard"
        # VAT portion contained within the inclusive line total
        (line_total_cents - (line_total_cents / (1 + STANDARD_VAT_RATE))).round
      else
        0
      end

    # Medical = the medical-aid (Discovery) portion (rate × qty), capped at the line total.
    # Self = what the patient pays out of pocket = line total − medical. When the Discovery rate is
    # unknown (medical_fee_cents nil), medical = 0 and the patient is liable for the whole line.
    if respond_to?(:medical_cents)
      med_unit = (respond_to?(:procedure_code) && procedure_code ? procedure_code.medical_fee_cents.to_i : 0)
      self.medical_cents = [ quantity.to_i * med_unit, line_total_cents ].min
      self.self_cents = line_total_cents - medical_cents
    end
  end

  def line_total = line_total_cents.to_i / 100.0
  def vat        = vat_cents.to_i / 100.0
  def medical    = respond_to?(:medical_cents) ? medical_cents.to_i / 100.0 : 0.0
  def self_portion = respond_to?(:self_cents) ? self_cents.to_i / 100.0 : line_total
end

# Shared line maths for estimate_lines and invoice_lines.
# VAT treatment: fees are stored VAT-INCLUSIVE (SA convention — see UNCERTAINTIES #17).
# Zero-rated (medical) lines carry no VAT; standard-rated (cosmetic, e.g. whitening) have 15%
# extracted from the inclusive price.
module BillableLine
  extend ActiveSupport::Concern

  STANDARD_VAT_RATE = 0.15

  included do
    before_validation :compute_totals
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
  end

  def line_total = line_total_cents.to_i / 100.0
  def vat        = vat_cents.to_i / 100.0
end

# Read-only view of the procedure-code catalogue (Phase 1). Additive — new route.
class ProcedureCodesController < ApplicationController
  def index
    codes = ProcedureCode.order(:code).to_a
    render inertia: "ProcedureCatalogue", props: {
      codes: codes.map { |c| code_props(c) },
      stats: {
        total: codes.size,
        priced: codes.count { |c| c.default_fee_cents.present? },
        zero_rated: codes.count { |c| c.vat_treatment == "zero_rated" },
        standard_rated: codes.count { |c| c.vat_treatment == "standard" }
      }
    }
  end

  private

  def code_props(c)
    {
      id: c.id,
      code: c.code,
      description: c.description,
      category: c.category,
      vat_treatment: c.vat_treatment,
      tooth_specific: c.tooth_specific,
      fee: c.default_fee_cents.present? ? (c.default_fee_cents / 100.0) : nil
    }
  end
end

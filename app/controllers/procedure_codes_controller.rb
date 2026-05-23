# Read-only view of the procedure-code catalogue (Phase 1). Additive — new route.
# P9.6 adds in-place editing of the `description` only (anyone can fix
# a bad description — fee / VAT / category stay admin-only and are
# managed via the seeds).
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

  # PATCH /procedure-codes/:id
  #
  # P9.6 — staff-editable description. Intentionally narrow: only the
  # description field is updatable through this endpoint. Code, fee,
  # VAT treatment, category, tooth_specific are NOT touchable from the
  # UI — those are catalogue-level decisions that go through the seed.
  def update
    code = ProcedureCode.find(params[:id])
    new_description = params.dig(:procedure_code, :description).to_s.strip

    if new_description.blank?
      return redirect_back fallback_location: procedure_codes_path,
        alert: "Description cannot be blank", status: :see_other
    end

    old_description = code.description
    if old_description == new_description
      return redirect_back fallback_location: procedure_codes_path,
        notice: "No changes", status: :see_other
    end

    code.update!(description: new_description)

    AuditService.log(
      action: "procedure_code.description_updated",
      summary: "Edited description for #{code.code}: \"#{old_description.to_s.truncate(40)}\" → \"#{new_description.truncate(40)}\"",
      resource: code,
      details: { code: code.code, from: old_description, to: new_description },
      performed_by: audit_performer,
      ip_address: request.remote_ip
    )

    redirect_back fallback_location: procedure_codes_path,
      notice: "Description updated for #{code.code}", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: procedure_codes_path,
      alert: e.record.errors.full_messages.to_sentence, status: :see_other
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

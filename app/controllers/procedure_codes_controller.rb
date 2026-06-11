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

  # PATCH /procedure-codes/:id — staff-editable description, fee, category, VAT.
  def update
    code  = ProcedureCode.find(params[:id])
    attrs = update_attrs
    if attrs.key?(:description) && attrs[:description].blank?
      return redirect_back fallback_location: procedure_codes_path,
        alert: "Description cannot be blank", status: :see_other
    end
    before = code.slice(:description, :default_fee_cents, :category, :vat_treatment)
    code.update!(attrs)
    audit("procedure_code.updated", "Edited #{code.code}", code, { before: before, after: attrs })
    redirect_back fallback_location: procedure_codes_path,
      notice: "Updated #{code.code}", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: procedure_codes_path,
      alert: e.record.errors.full_messages.to_sentence, status: :see_other
  end

  # POST /procedure-codes — add a new tariff code.
  def create
    p = params.require(:procedure_code).permit(:code, :description, :fee, :category, :vat_treatment)
    code = ProcedureCode.create!(
      code:              p[:code].to_s.strip,
      description:       p[:description].to_s.strip,
      default_fee_cents: p[:fee].present? ? (p[:fee].to_f * 100).round : nil,
      category:          p[:category].presence || "other",
      vat_treatment:     p[:vat_treatment].presence || "standard",
      active:            true
    )
    audit("procedure_code.created", "Added #{code.code} — #{code.description}", code, { code: code.code })
    redirect_back fallback_location: procedure_codes_path,
      notice: "Added #{code.code}", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: procedure_codes_path,
      alert: e.record.errors.full_messages.to_sentence, status: :see_other
  end

  # POST /procedure-codes/bulk-uplift — apply a % change to every priced fee
  # (the annual SADA fee increase). Rounds to the nearest cent.
  def bulk_update
    pct = params[:percent].to_f
    if pct.zero?
      return redirect_back fallback_location: procedure_codes_path,
        alert: "Enter a percentage, e.g. 6", status: :see_other
    end
    # Sanity bound — this writes EVERY fee immediately (no preview), so a fat-finger
    # like "600" instead of "6" would 7× the whole schedule, and < -100% would make
    # fees negative. -90%..100% is generous for any real annual uplift/discount.
    if pct < -90 || pct > 100
      return redirect_back fallback_location: procedure_codes_path,
        alert: "Uplift must be between -90% and 100% (got #{pct}%) — re-enter to confirm", status: :see_other
    end
    factor = 1 + (pct / 100.0)
    n = 0
    ProcedureCode.where.not(default_fee_cents: nil).find_each do |c|
      c.update_columns(default_fee_cents: (c.default_fee_cents * factor).round)
      n += 1
    end
    audit("procedure_code.bulk_uplift", "Applied #{pct}% uplift to #{n} fees", nil, { percent: pct, count: n })
    redirect_back fallback_location: procedure_codes_path,
      notice: "Applied #{pct}% to #{n} fees", status: :see_other
  end

  private

  def update_attrs
    p = params.require(:procedure_code).permit(:description, :fee, :category, :vat_treatment)
    a = {}
    a[:description]       = p[:description].to_s.strip if p.key?(:description)
    a[:default_fee_cents] = (p[:fee].to_f * 100).round if p[:fee].present?
    a[:category]          = p[:category] if p[:category].present?
    a[:vat_treatment]     = p[:vat_treatment] if p[:vat_treatment].present?
    a
  end

  def audit(action, summary, resource, details)
    AuditService.log(action: action, summary: summary, resource: resource,
      details: details, performed_by: audit_performer, ip_address: request.remote_ip)
  rescue => e
    Rails.logger.warn("[procedure_codes] audit failed: #{e.message}")
  end

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

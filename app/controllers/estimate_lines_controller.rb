# Add / amend / remove estimate line items (tariff code, tooth, qty, fee).
# compute_totals (BillableLine) derives line/VAT/medical/self; recalc rolls the
# estimate header total. Reception + dentist edit estimates here.
class EstimateLinesController < ApplicationController
  # POST /estimates/:estimate_id/lines
  def create
    estimate = Estimate.find(params[:estimate_id])
    line = estimate.estimate_lines.new
    apply(line)
    line.save!
    recalc(estimate)
    redirect_back fallback_location: estimate_path(estimate), notice: "Line added", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: estimates_path, alert: e.record.errors.full_messages.to_sentence, status: :see_other
  end

  # PATCH /estimate_lines/:id
  def update
    line = EstimateLine.find(params[:id])
    apply(line)
    line.save!
    recalc(line.estimate)
    redirect_back fallback_location: estimate_path(line.estimate), notice: "Line updated", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: estimates_path, alert: e.record.errors.full_messages.to_sentence, status: :see_other
  end

  # DELETE /estimate_lines/:id
  def destroy
    line = EstimateLine.find(params[:id])
    estimate = line.estimate
    line.destroy!
    recalc(estimate)
    redirect_back fallback_location: estimate_path(estimate), notice: "Line removed", status: :see_other
  end

  private

  def apply(line)
    p  = params.require(:estimate_line).permit(:procedure_code_id, :code, :description, :tooth_number, :quantity, :fee, :icd10_code)
    pc = (ProcedureCode.find_by(id: p[:procedure_code_id]) if p[:procedure_code_id].present?)
    line.procedure_code_id = p[:procedure_code_id].presence
    line.code         = p[:code].presence || pc&.code
    line.description  = p[:description].presence || pc&.description
    line.tooth_number = p[:tooth_number].presence
    line.quantity     = [ p[:quantity].to_i, 1 ].max
    line.icd10_code   = p[:icd10_code].presence if p.key?(:icd10_code)  # dentist override; blank re-defaults via callback
    line.vat_treatment = pc&.vat_treatment.presence || line.vat_treatment.presence || "standard"
    line.unit_fee_cents =
      if    p[:fee].present?            then (p[:fee].to_f * 100).round
      elsif pc&.default_fee_cents       then pc.default_fee_cents
      else  line.unit_fee_cents.to_i
      end
  end

  def recalc(estimate)
    estimate.estimate_lines.reload
    estimate.recalculate
    estimate.save!
  end
end

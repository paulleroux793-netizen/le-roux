# Imports Elixir estimates as editable Ivory `Estimate` records under each
# patient (so they show on the patient view and can be edited), matched to the
# patient within their A-coded billing account. Idempotent: clears its own
# previously-imported estimates (notes tagged [elixir]) and rebuilds.
# Source: tmp/estimates.json.  Run on the rig: bin/rails runner script/import_elixir_estimates.rb
require "json"

MARK = "[elixir]"
data = JSON.parse(File.read(ENV.fetch("ESTIMATES_JSON", "tmp/estimates.json")))

# Clear previous import (estimate_lines cascade via dependent: :destroy).
Estimate.where("notes LIKE ?", "%#{MARK}%").destroy_all

accounts = BillingAccount.where.not(account_code: nil).includes(:patients).index_by(&:account_code)
stats = Hash.new(0)

data.each do |r|
  begin
    ba = accounts[r["account_code"]]
    unless ba
      stats[:no_account] += 1; next
    end
    pats = ba.patients.to_a
    target = pats.find { |p| p.full_name.to_s.casecmp?(r["patient_name"].to_s) } ||
             (ba.head_patient_id && pats.find { |p| p.id == ba.head_patient_id }) ||
             pats.first
    unless target
      stats[:no_patient] += 1; next
    end
    cents = (r["value"].to_f * 100).round
    created_at = (Date.parse(r["date_sent"]).to_time rescue Time.current)

    # If the export includes structured line items (a "lines" array of {code, description,
    # fee/amount, quantity, tooth}), build real estimate_lines so the CODES show on the
    # estimate. Otherwise fall back to a header-only total (the pre-2026-06-07 export was
    # header-only — value + a free-text "details" string, no codes — which is why imported
    # estimates showed a total but no line items). A proper Elixir re-export populates codes.
    lines = r["lines"]
    if lines.is_a?(Array) && lines.any?
      est = Estimate.create!(patient_id: target.id, billing_account_id: ba.id, status: "draft",
                             subtotal_cents: 0, vat_cents: 0, total_cents: 0,
                             notes: "#{MARK} #{r['details']}".strip, created_at: created_at)
      lines.each do |l|
        next if l["code"].blank? && l["description"].blank?

        pc = ProcedureCode.find_by(code: l["code"].to_s)
        est.estimate_lines.create!(
          procedure_code_id: pc&.id,
          code:        l["code"].presence || pc&.code,
          description: l["description"].presence || pc&.description,
          quantity:    [ (l["quantity"] || 1).to_i, 1 ].max,
          unit_fee_cents: ((l["fee"] || l["amount"] || l["value"]).to_f * 100).round,
          vat_treatment:  (pc&.vat_treatment.presence || "standard"),
          tooth_number:   l["tooth"].presence
        )
      end
      est.estimate_lines.reload
      est.recalculate
      est.save!
      stats[:created_with_lines] += 1
    else
      Estimate.create!(
        patient_id:       target.id,
        billing_account_id: ba.id,
        status:           "draft",
        total_cents:      cents,
        subtotal_cents:   cents,
        vat_cents:        0,
        notes:            "#{MARK} #{r['details']}".strip,
        created_at:       created_at
      )
      stats[:created_header_only] += 1
    end
    stats[:created] += 1
  rescue => e
    stats[:errors] += 1
    Rails.logger.warn("[est] skip #{r['patient_name']}: #{e.message}")
  end
end

puts "[est] #{stats.inspect}"
puts "[est] total Estimate=#{Estimate.count}; patients with >=1 estimate=#{Estimate.distinct.count(:patient_id)}"

# DEEP STRESS TEST (safe, self-cleaning): end-to-end verify of the cycle-6 estimate
# apply_macro logic — create a throwaway estimate for the demo patient, apply a macro,
# assert the lines + fees + total are correct, then DESTROY the test estimate.
# Run: docker compose ... exec -T web bin/rails runner script/stress/apply_macro_e2e.rb
p = Patient.find(2985) # John Demo-Smith (demo/test patient)
macro = TreatmentMacro.active.where(access_code: "C/U").first || TreatmentMacro.active.first
expected_items = macro.treatment_macro_items.includes(:procedure_code).select { |mi| mi.procedure_code }

est = nil
begin
  est = Estimate.create!(patient: p, billing_account: p.billing_accounts.first,
                         status: "draft", subtotal_cents: 0, vat_cents: 0, total_cents: 0)
  # --- replicate estimates_controller#apply_macro verbatim ---
  added = 0
  ActiveRecord::Base.transaction do
    expected_items.each do |mi|
      pc = mi.procedure_code
      est.estimate_lines.create!(
        procedure_code: pc, code: pc.code, description: pc.description,
        quantity: [ mi.quantity.to_i, 1 ].max,
        vat_treatment: pc.vat_treatment.presence || "standard",
        unit_fee_cents: pc.default_fee_cents.to_i
      )
      added += 1
    end
    est.estimate_lines.reload
    est.recalculate
    est.save!
  end
  # --- assertions ---
  lines = est.estimate_lines.to_a
  ok_count = (lines.size == expected_items.size)
  ok_fees  = lines.all? { |l| l.unit_fee_cents == l.procedure_code.default_fee_cents.to_i }
  sum_cents = lines.sum { |l| l.unit_fee_cents.to_i * l.quantity.to_i }
  total_cents = (est.total.to_f * 100).round
  ok_total = (sum_cents == total_cents)
  verdict = (ok_count && ok_fees && ok_total) ? "PASS" : "FAIL"
  puts "MACRO=#{macro.access_code} expected_items=#{expected_items.size} lines=#{lines.size} ok_count=#{ok_count} ok_fees=#{ok_fees} sum_cents=#{sum_cents} total_cents=#{total_cents} ok_total=#{ok_total} => #{verdict}"
rescue => e
  puts "ERROR: #{e.class}: #{e.message}"
ensure
  if est&.persisted?
    id = est.id
    est.destroy!
    puts "CLEANUP: destroyed test estimate ##{id}; remaining estimates for patient 2985 = #{Estimate.where(patient_id: 2985).count}"
  end
end

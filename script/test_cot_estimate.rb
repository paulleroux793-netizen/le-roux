cot = CourseOfTreatment.find(79)
pc = ProcedureCode.where("default_fee_cents > 0").first
# add a planned treatment item (mirror what charting/add-item does)
ti = cot.treatment_items.create!(procedure_code: pc, fee_cents: pc.default_fee_cents, tooth_number: "11", status: "planned")
cot.reload
puts "COT #79: items=#{cot.treatment_items.count} estimated_total=R#{cot.estimated_total}"
est = Estimate.from_course(cot)
est.save! unless est.persisted?
puts "estimate ##{est.id}: lines=#{est.estimate_lines.count} total=R#{est.total} (first line: #{est.estimate_lines.first&.code} R#{est.estimate_lines.first&.unit_fee_cents.to_i/100.0})"
puts "LINK OK: lines_carry=#{est.estimate_lines.count == cot.treatment_items.count} total_match=#{est.total.to_f == cot.estimated_total.to_f}"

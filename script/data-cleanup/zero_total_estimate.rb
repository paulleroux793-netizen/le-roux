# script/data-cleanup/zero_total_estimate.rb  (DATA ITEM #5 — for Paul)
#
# WHAT: Finds estimates with a zero total (total_cents 0/null). WHY: stale empty
#       draft estimates clutter the list and can be safely removed. RISK: LOW —
#       only an EMPTY (0 line items), OLD (>1 year), DRAFT, non-demo estimate is a
#       delete candidate; everything else is only listed, never touched.
#
# DRY-RUN (default): bin/rails runner script/data-cleanup/zero_total_estimate.rb
#   → prints every zero-total estimate, marking which are delete-candidates.
# APPLY:  APPLY=1 bin/rails runner script/data-cleanup/zero_total_estimate.rb
#   → deletes ONLY the candidates (empty + old + draft + non-demo), in a transaction.
#
# ROLLBACK: restore the pre-run DB backup. (A deleted empty draft has no lines and
# no generated invoice, so there is nothing else to restore.)
#
# As of 2026-06-06 inspection: 1 real candidate — #31 EST-2026-000001
# (Lance Van Vuuuren, draft, 0 lines, created 2022-10-11). Review before APPLY.

apply = ENV["APPLY"] == "1"

zero = Estimate.where("total_cents = 0 OR total_cents IS NULL").includes(:patient, :estimate_lines)

def candidate?(e)
  e.estimate_lines.empty? &&
    e.status.to_s == "draft" &&
    e.created_at && e.created_at < 1.year.ago &&
    !e.patient&.notes.to_s.include?("[demo]")
end

candidates = zero.select { |e| candidate?(e) }
others     = zero.reject { |e| candidate?(e) }

puts "=== Zero-total estimates (#{apply ? 'APPLY' : 'DRY-RUN'}) ==="
puts "Total zero-total estimates: #{zero.size}"
puts
puts "DELETE CANDIDATES (empty + >1yr + draft + non-demo) — #{candidates.size}:"
candidates.each { |e| puts "  ##{e.id} #{e.estimate_number} pt=#{e.patient&.full_name} created=#{e.created_at&.to_date}" }
puts
unless others.empty?
  puts "LISTED ONLY (NOT a delete candidate — has lines, or recent, or not draft) — #{others.size}:"
  others.each { |e| puts "  ##{e.id} #{e.estimate_number} pt=#{e.patient&.full_name} status=#{e.status} lines=#{e.estimate_lines.size} created=#{e.created_at&.to_date}" }
  puts
end

if apply
  ActiveRecord::Base.transaction do
    candidates.each do |e|
      e.estimate_lines.destroy_all
      e.destroy!
      puts "  DELETED ##{e.id} #{e.estimate_number}"
    end
  end
  puts "APPLY complete — deleted #{candidates.size}."
else
  puts "DRY-RUN only — nothing changed. Re-run with APPLY=1 (after a backup) to delete the candidates."
end

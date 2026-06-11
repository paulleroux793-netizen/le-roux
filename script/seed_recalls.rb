# Generate an actionable recall worklist: 6-month checkup recall from each patient's
# last visit (= last invoice date). Keep only the actionable window per best practice:
# overdue up to 12 months OR due within the next 6 weeks. Idempotent (skips open recalls).
created = 0; skipped = 0
Patient.joins(:invoices).distinct.find_each do |p|
  last = p.invoices.maximum(:invoice_date)
  next unless last
  due = last.to_date + 6.months
  if due > Date.current + 42 || due < Date.current - 365
    skipped += 1; next
  end
  next if Recall.where(patient_id: p.id, status: %w[due contacted booked]).exists?
  Recall.create!(patient: p, due_on: due, status: "due")
  created += 1
end
overdue = Recall.overdue.count
puts "[recalls] created #{created} (skipped #{skipped} outside window); total=#{Recall.count}, overdue=#{overdue}, due-soon=#{Recall.due.where('due_on >= ?', Date.current).count}"

# Import recent Elixir ledger as Ivory invoices (+lines) and payments, with
# payments allocated oldest-first to invoices so account balances are correct.
# Idempotent: clears its own [elixir]-tagged invoices/payments. Source: tmp/ledger.json
require "json"
MARK = "[elixir]"
data = JSON.parse(File.read(ENV.fetch("LEDGER_JSON", "tmp/ledger.json")))

Payment.where("notes LIKE ?", "%#{MARK}%").delete_all
Invoice.where("notes LIKE ?", "%#{MARK}%").destroy_all

accounts = BillingAccount.where.not(account_code: nil).includes(:patients).index_by(&:account_code)
inv_by = Hash.new { |h, k| h[k] = [] }
data["invoices"].each { |i| inv_by[i["account_code"]] << i }
pay_by = Hash.new { |h, k| h[k] = [] }
data["payments"].each { |p| pay_by[p["account_code"]] << p }
s = Hash.new(0)

accounts.each do |code, ba|
  invs = inv_by[code].sort_by { |i| i["date"].to_s }
  pays = pay_by[code]
  next if invs.empty? && pays.empty?
  patient = ba.head_patient || ba.patients.first
  next unless patient
  begin
    remaining = pays.sum { |p| (p["amount"].to_f * 100).round }
    invs.each do |inv|
      total = inv["lines"].sum { |l| (l["amount"].to_f * 100).round }
      vat   = inv["lines"].sum { |l| (l["vat"].to_f * 100).round }
      next if total <= 0
      applied = [[remaining, total].min, 0].max
      remaining -= applied
      invoice = Invoice.create!(
        billing_account: ba, patient: patient,
        invoice_date: (Date.parse(inv["date"]) rescue Date.current),
        total_cents: total, vat_cents: vat, subtotal_cents: total - vat,
        paid_cents: applied,
        status: (applied >= total ? "paid" : (applied.positive? ? "part_paid" : "open")),
        provider_name: inv["provider"],
        notes: MARK
      )
      inv["lines"].each do |l|
        cents = (l["amount"].to_f * 100).round
        invoice.invoice_lines.create!(code: l["code"], description: l["description"].to_s[0, 120],
          quantity: 1, unit_fee_cents: cents, line_total_cents: cents, vat_cents: (l["vat"].to_f * 100).round)
      end
      s[:invoices] += 1
    end
    pays.each do |p|
      cents = (p["amount"].to_f * 100).round
      next if cents <= 0
      Payment.create!(billing_account: ba, patient: patient, amount_cents: cents,
        method: p["method"], received_at: (Date.parse(p["date"]).to_time rescue Time.current), notes: MARK)
      s[:payments] += 1
    end
  rescue => e
    s[:errors] += 1; Rails.logger.warn("[ledger] #{code}: #{e.message}")
  end
end
out = Invoice.where(status: %w[open part_paid]).sum { |i| i.total_cents - i.paid_cents } / 100.0
puts "[ledger] #{s.inspect}"
puts "[ledger] Invoice=#{Invoice.count}, Payment=#{Payment.count}, total outstanding R#{out.round(2)}"

# TransactionReport — practice cash-up / transaction report for a DAY, MONTH, or YEAR.
# Lists every active (non-reversed) payment in the range with its method + party, and totals
# broken down by payment method (card/cash/eft/credit). Refunds/reversals count as money OUT
# (negative). Drives the on-screen view, the CSV (Excel) export, and the PDF.
class TransactionReport
  PERIODS = %w[day month year].freeze
  OUTWARD = %w[refund reversal].freeze

  Row = Struct.new(:at, :party, :method, :kind, :reference, :amount_cents, keyword_init: true)

  attr_reader :period, :date, :range

  def initialize(period: "day", date: nil)
    @period = PERIODS.include?(period.to_s) ? period.to_s : "day"
    @date   = parse_date(date)
    @range  = self.class.range_for(@period, @date)
  end

  def self.range_for(period, date)
    case period.to_s
    when "year"  then date.beginning_of_year.beginning_of_day..date.end_of_year.end_of_day
    when "month" then date.beginning_of_month.beginning_of_day..date.end_of_month.end_of_day
    else              date.beginning_of_day..date.end_of_day
    end
  end

  def rows
    @rows ||= scope.order(:received_at).map do |p|
      Row.new(
        at: p.received_at,
        party: party_for(p),
        method: p.method,
        kind: p.kind,
        reference: p.reference.presence || (p.invoice_id ? "INV ##{p.invoice_id}" : nil),
        amount_cents: signed_cents(p)
      )
    end
  end

  # Money in (payment/deposit) minus money out (refund/reversal), per payment method.
  def totals_by_method
    @totals_by_method ||= begin
      t = Payment::METHODS.index_with { 0 }
      scope.each { |p| t[p.method] = t[p.method].to_i + signed_cents(p) }
      t
    end
  end

  def total_cents = rows.sum(&:amount_cents)
  def count = rows.size

  # Per-dentist PRODUCTION — invoices raised in the range, grouped by provider. This is the
  # accurate "who brought in what" split (payments are account-level and not dentist-tagged).
  def production_by_provider
    @production_by_provider ||= Invoice.where(void: false)
      .where(invoice_date: range.begin.to_date..range.end.to_date)
      .group(:provider_name)
      .pluck(Arel.sql("provider_name, SUM(total_cents), COUNT(*)"))
      .map { |name, cents, cnt| { provider: name.presence || "— Unassigned —", production_cents: cents.to_i, count: cnt } }
      .sort_by { |h| -h[:production_cents] }
  end

  def production_total_cents = production_by_provider.sum { |h| h[:production_cents] }

  LineRow = Struct.new(:date, :patient, :tooth, :account_code, :code, :description,
                       :self_cents, :medical_cents, :total_cents, :qty, keyword_init: true)

  # Per-dentist TURNOVER, line by line — every charge code billed in the range. Mirrors the
  # Elixir "Transaction Analysis": grouped by provider, each row one invoice line (tariff code,
  # tooth, units, patient/scheme split, line total). => { "DR CHALITA LE ROUX" => [LineRow, …] }
  def turnover_by_provider
    @turnover_by_provider ||= begin
      grouped = Hash.new { |h, k| h[k] = [] }
      InvoiceLine.joins(:invoice)
        .where(invoices: { void: false, invoice_date: range.begin.to_date..range.end.to_date })
        .includes(invoice: [ :patient, :billing_account ])
        .order(Arel.sql("invoices.provider_name NULLS LAST, invoices.invoice_date, invoices.invoice_number"))
        .each do |l|
          inv = l.invoice
          grouped[inv.provider_name.presence || "— Unassigned —"] << LineRow.new(
            date: inv.invoice_date, patient: inv.patient&.full_name, tooth: l.tooth_number,
            account_code: inv.billing_account&.account_code, code: l.code, description: l.description,
            self_cents: l.self_cents.to_i, medical_cents: l.medical_cents.to_i,
            total_cents: l.line_total_cents.to_i, qty: l.quantity.to_i
          )
        end
      grouped
    end
  end

  def turnover_provider_totals = turnover_by_provider.transform_values { |rows| rows.sum(&:total_cents) }
  def turnover_total_cents = turnover_by_provider.values.sum { |rows| rows.sum(&:total_cents) }

  def label
    case period
    when "year"  then date.strftime("%Y")
    when "month" then date.strftime("%B %Y")
    else              date.strftime("%A, %-d %B %Y")
    end
  end

  private

  def scope
    Payment.active.where(received_at: range).includes(:patient, :billing_account, :invoice)
  end

  def signed_cents(p)
    OUTWARD.include?(p.kind) ? -p.amount_cents.to_i : p.amount_cents.to_i
  end

  def party_for(p)
    p.patient&.full_name.presence ||
      p.billing_account&.billing_name.presence ||
      p.billing_account&.account_code.presence || "—"
  end

  def parse_date(date)
    return Date.current if date.blank?
    date.is_a?(Date) ? date : (Date.parse(date.to_s) rescue Date.current)
  end
end

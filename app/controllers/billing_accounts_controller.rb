# Billing accounts (the unit that pays). List + show with a transactions ledger
# (invoices = debit, payments = credit, running balance), a date-range filter, and
# a printable statement PDF. Tax invoices are per-invoice (each is a date's invoice).
class BillingAccountsController < ApplicationController
  def index
    accounts = BillingAccount.includes(:patients).order(:account_code).limit(5000).to_a
    # Outstanding per account in ONE grouped query (no N+1) so reception sees debtors at a glance.
    outstanding = Invoice.where(status: %w[open part_paid]).group(:billing_account_id).sum("total_cents - paid_cents")
    render inertia: "BillingAccounts", props: {
      accounts: accounts.map { |a| list_props(a, outstanding[a.id].to_i) },
      stats: { total: BillingAccount.count, owing: outstanding.values.count { |c| c.to_i.positive? } }
    }
  end

  def show
    account = BillingAccount.includes(account_patients: :patient).find(params[:id])
    from = parse_date(params[:from]) || 1.year.ago.to_date
    to   = parse_date(params[:to])   || Date.current

    opening = opening_balance(account, from)
    running = opening
    txns = ledger(account, from, to).map do |e|
      running += e[:debit] - e[:credit]
      { date: e[:date].iso8601, ref: e[:ref], description: e[:desc],
        debit: e[:debit] / 100.0, credit: e[:credit] / 100.0, balance: running / 100.0 }
    end
    billed = account.invoices.where(void: false).sum(:total_cents).to_i
    paid   = account.payments.inward.sum(:amount_cents).to_i # active real money in (excludes reversed + internal credit moves)

    # Per-member next-appointment + outstanding in TWO batched queries (was an N+1: ~2 per
    # member — 6 members = 14 queries; a big family account scaled linearly).
    member_pids   = account.account_patients.map(&:patient_id)
    next_appt_by  = Appointment.where(patient_id: member_pids).where("start_time > ?", Time.current)
                               .where.not(status: :cancelled).order(:start_time).group_by(&:patient_id)
    outstanding_by = Invoice.where(patient_id: member_pids, status: %w[open part_paid])
                            .group(:patient_id).sum("total_cents - paid_cents")

    render inertia: "BillingAccountShow", props: {
      account: {
        id: account.id, account_code: account.account_code, billing_name: account.billing_name,
        email: account.email, phone: account.phone,
        address: [ account.address_line1, account.address_line2, account.city, account.postal_code ].compact_blank.join(", "),
        members: account.account_patients.map { |ap|
          pt = ap.patient
          na = next_appt_by[ap.patient_id]&.first
          { id: ap.patient_id, name: pt.full_name, phone: pt.display_phone, relationship: ap.relationship,
            next_appointment: na&.start_time&.iso8601,
            outstanding: (outstanding_by[ap.patient_id].to_i / 100.0) }
        }
      },
      period: { from: from.iso8601, to: to.iso8601 },
      opening_balance: opening / 100.0,
      closing_balance: running / 100.0,
      balance: { billed: billed / 100.0, paid: paid / 100.0, outstanding: (billed - paid) / 100.0,
                 credit: account.credit_cents.to_i / 100.0 },
      transactions: txns,
      invoices: account.invoices.where(invoice_date: from..to).order(invoice_date: :desc).limit(300).map { |i|
        { id: i.id, number: i.invoice_number, date: i.invoice_date.iso8601, total: i.total_cents.to_i / 100.0, status: i.status, provider: i.provider_name }
      }
    }
  end

  # GET /accounts/:id/statement.pdf?from=…&to=…  — printable statement for a range.
  def statement
    account = BillingAccount.find(params[:id])
    from = parse_date(params[:from]) || 1.year.ago.to_date
    to   = parse_date(params[:to])   || Date.current
    send_data StatementPdf.render(account, from: from, to: to),
      filename: "statement-#{account.account_code}-#{to.iso8601}.pdf",
      type: "application/pdf", disposition: "inline"
  end

  # POST /accounts/:id/receive_payment — one payment, allocated oldest-first across the
  # account's open invoices, remainder banked as credit.
  def receive_payment
    account = BillingAccount.find(params[:id])
    cents = (params[:amount].to_f * 100).round
    method = params[:method].to_s
    return reject(account, "Amount must be between R0 and R20,000,000") if cents <= 0 || cents > Payment::MAX_CENTS
    return reject(account, "Unknown payment method") unless %w[card cash eft].include?(method)

    result = account.receive_payment(cents, method: method, reference: params[:reference].presence)
    AuditService.log(action: "account.payment_received",
      summary: "#{account.account_code}: R#{r(cents)} #{method.upcase} → #{result[:allocated].size} invoice(s), R#{r(result[:to_credit_cents])} to credit",
      resource: account, performed_by: audit_performer, ip_address: request.remote_ip)
    redirect_back fallback_location: billing_account_path(account), notice: "Payment allocated across the account.", status: :see_other
  end

  # POST /accounts/:id/deposit — take an advance deposit, banked as account credit.
  def deposit
    account = BillingAccount.find(params[:id])
    cents = (params[:amount].to_f * 100).round
    method = params[:method].to_s
    return reject(account, "Amount must be between R0 and R20,000,000") if cents <= 0 || cents > Payment::MAX_CENTS
    return reject(account, "Unknown payment method") unless %w[card cash eft].include?(method)

    account.payments.create!(method: method, kind: "deposit", is_deposit: true, amount_cents: cents,
                             patient: account.head_patient, reference: params[:reference].presence)
    AuditService.log(action: "account.deposit",
      summary: "#{account.account_code}: R#{r(cents)} #{method.upcase} deposit banked as credit",
      resource: account, performed_by: audit_performer, ip_address: request.remote_ip)
    redirect_back fallback_location: billing_account_path(account), notice: "Deposit banked as account credit.", status: :see_other
  end

  # POST /accounts/:id/apply_credit — move available account credit onto an invoice.
  def apply_credit
    account = BillingAccount.find(params[:id])
    invoice = account.invoices.find(params[:invoice_id])
    cents = params[:amount].present? ? (params[:amount].to_f * 100).round : nil
    applied = account.apply_credit_to(invoice, cents)
    AuditService.log(action: "account.credit_applied",
      summary: "#{account.account_code}: applied R#{r(applied)} credit to #{invoice.invoice_number}",
      resource: account, performed_by: audit_performer, ip_address: request.remote_ip) if applied.positive?
    redirect_back fallback_location: billing_account_path(account),
      notice: (applied.positive? ? "Applied R#{r(applied)} credit to #{invoice.invoice_number}." : "No credit available to apply."),
      status: :see_other
  end

  # POST /accounts/:id/refund — pay available account credit back to the patient.
  def refund
    account = BillingAccount.find(params[:id])
    cents = (params[:amount].to_f * 100).round
    method = params[:method].to_s
    return reject(account, "Amount must be between R0 and R20,000,000") if cents <= 0 || cents > Payment::MAX_CENTS
    return reject(account, "Unknown payment method") unless %w[card cash eft].include?(method)

    refunded = account.refund!(cents, method: method, reason: params[:reason].presence)
    if refunded.positive?
      AuditService.log(action: "account.refund",
        summary: "#{account.account_code}: refunded R#{r(refunded)} (#{method.upcase})#{params[:reason].present? ? " — #{params[:reason]}" : ''}",
        resource: account, performed_by: audit_performer, ip_address: request.remote_ip)
    end
    redirect_back fallback_location: billing_account_path(account),
      notice: (refunded.positive? ? "Refunded R#{r(refunded)} from account credit." : "No credit available to refund."),
      status: :see_other
  end

  private

  def r(cents) = format("%.2f", cents.to_i / 100.0)

  def reject(account, msg)
    redirect_back fallback_location: billing_account_path(account), alert: msg, status: :see_other
  end

  def parse_date(str)
    Date.parse(str.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def ledger(account, from, to)
    list = []
    account.invoices.where(invoice_date: from..to).order(:invoice_date).each do |i|
      desc = i.provider_name.present? ? "Treatment invoice · #{i.provider_name}" : "Treatment invoice"
      list << { date: i.invoice_date.to_date, ref: i.invoice_number, desc: desc, debit: i.total_cents.to_i, credit: 0 }
    end
    account.payments.inward.where(received_at: from.beginning_of_day..to.end_of_day).order(:received_at).each do |p|
      label = p.kind == "deposit" ? "Deposit (#{p.method})" : "Payment (#{p.method})"
      list << { date: p.received_at.to_date, ref: (p.reference.presence || p.method.to_s.upcase), desc: label, debit: 0, credit: p.amount_cents.to_i }
    end
    list.sort_by { |e| e[:date] }
  end

  def opening_balance(account, from)
    account.invoices.where(void: false).where("invoice_date < ?", from).sum(:total_cents).to_i -
      account.payments.inward.where("received_at < ?", from.beginning_of_day).sum(:amount_cents).to_i
  end

  def list_props(a, outstanding_cents = 0)
    { id: a.id, account_code: a.account_code, billing_name: a.billing_name, phone: a.phone, member_count: a.patients.size,
      outstanding: (outstanding_cents / 100.0) }
  end
end

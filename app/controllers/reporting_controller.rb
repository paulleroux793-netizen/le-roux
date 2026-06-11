# Reporting / KPIs (Phase 5.3). Read-only practice metrics. Additive route.
# C3 — financial KPIs now correlate with CLINICAL metrics (case acceptance,
# treatment-plan completion, chair hours) so Paul can read the practice's
# health in one screen rather than chasing numbers across pages.
class ReportingController < ApplicationController
  def index
    month_start = Time.current.beginning_of_month
    today       = Date.current

    # ── C3 clinical KPIs ──────────────────────────────────────────
    estimates_this_month = Estimate.where("created_at >= ?", month_start).to_a
    accepted_count       = estimates_this_month.count { |e| e.status == "accepted" }
    estimates_total      = estimates_this_month.size
    case_acceptance_rate = estimates_total.zero? ? nil :
                           ((accepted_count.to_f / estimates_total) * 100).round(1)

    cots_last_quarter = CourseOfTreatment.includes(:treatment_items)
                                         .where("created_at >= ?", 3.months.ago)
                                         .to_a
    completed_cots = cots_last_quarter.count { |c|
      c.treatment_items.any? && c.treatment_items.all? { |i| %w[completed voided].include?(i.status) }
    }
    treatment_completion_rate = cots_last_quarter.size.zero? ? nil :
                                ((completed_cots.to_f / cots_last_quarter.size) * 100).round(1)

    chair_hours_today = Appointment.where(start_time: today.all_day)
                                   .where.not(status: :cancelled)
                                   .to_a
                                   .sum { |a| (a.end_time - a.start_time) / 3600.0 }

    production_month  = (Invoice.where(void: false).where("invoice_date >= ?", month_start.to_date).sum(:total_cents) / 100.0)
    collections_month = (Payment.where("received_at >= ?", month_start).sum(:amount_cents) / 100.0)
    # Collection rate — "are we actually getting paid for the work we do?" (benchmark #1)
    collection_rate   = production_month > 0 ? ((collections_month / production_month) * 100).round(1) : nil
    # No-show rate over the last 90 days of past appointments — a key practice-health metric.
    past_appts   = Appointment.where(start_time: 90.days.ago..Time.current)
    no_show_rate = past_appts.count.positive? ? ((past_appts.where(status: :no_show).count.to_f / past_appts.count) * 100).round(1) : nil
    # Aged debt — outstanding balance bucketed by age since invoice_date (owner chases 90+).
    aged = { current: 0, d31_60: 0, d61_90: 0, d90plus: 0 }
    Invoice.outstanding.pluck(:invoice_date, :total_cents, :paid_cents).each do |d, tot, paid|
      bal = tot.to_i - paid.to_i
      next if bal <= 0
      age = d ? (Date.current - d).to_i : 0
      key = age <= 30 ? :current : age <= 60 ? :d31_60 : age <= 90 ? :d61_90 : :d90plus
      aged[key] += bal
    end
    aged_debt = aged.transform_values { |c| c / 100.0 }

    render inertia: "Reporting", props: {
      kpis: {
        production_month: production_month,
        collections_month: collections_month,
        collection_rate: collection_rate,
        outstanding: (Invoice.outstanding.sum("total_cents - paid_cents") / 100.0),
        invoices_total: Invoice.count,
        estimates_open: Estimate.where(status: %w[draft sent]).count,
        courses_open: CourseOfTreatment.open.count,
        imaging_needs_match: ImagingStudy.needs_match.count,
        recalls_due: Recall.where(status: "due").where("due_on <= ?", Date.current).count,
        # C3 clinical-context KPIs
        case_acceptance_rate: case_acceptance_rate,
        estimates_this_month: estimates_total,
        treatment_completion_rate: treatment_completion_rate,
        chair_hours_today: chair_hours_today.round(2),
        no_show_rate: no_show_rate
      },
      production_by_setting: CourseOfTreatment.group(:setting).count,
      invoices_by_status: Invoice.group(:status).count,
      # Per-dentist production this month — leverages the provider distinction on invoices
      # so the owner sees Dr Chalita vs Dr Eliska at a glance.
      production_by_provider: Invoice.where(void: false).where("invoice_date >= ?", month_start.to_date)
        .group(:provider_name)
        .pluck(Arel.sql("provider_name, SUM(total_cents), COUNT(*)"))
        .map { |name, cents, cnt| { provider: name.presence || "— unassigned —", production: cents.to_i / 100.0, invoices: cnt } }
        .sort_by { |h| -h[:production] },
      aged_debt: aged_debt
    }
  end

  # GET /reporting/transactions(.:format)?period=day|month|year&date=YYYY-MM-DD
  # Practice cash-up / transaction report — money received in the range, broken down by
  # method (card/cash/eft/credit). HTML (Inertia page), CSV (Excel), or PDF.
  def transactions
    report = TransactionReport.new(period: params[:period], date: params[:date].presence)
    respond_to do |format|
      format.html { render inertia: "TransactionReport", props: transaction_props(report) }
      format.csv do
        send_data TransactionReportCsv.render(report),
          filename: "transactions-#{report.period}-#{report.date.iso8601}.csv", type: "text/csv"
      end
      format.pdf do
        send_data TransactionReportPdf.render(report),
          filename: "transactions-#{report.period}-#{report.date.iso8601}.pdf",
          type: "application/pdf", disposition: "inline"
      end
    end
  end

  private

  def transaction_props(report)
    {
      period: report.period,
      date: report.date.iso8601,
      label: report.label,
      rows: report.rows.map { |r|
        { at: r.at.iso8601, time: r.at.strftime("%-d %b %Y %H:%M"), party: r.party,
          method: r.method, kind: r.kind, reference: r.reference, amount: r.amount_cents / 100.0 }
      },
      totals_by_method: report.totals_by_method.transform_values { |c| c / 100.0 },
      total: report.total_cents / 100.0,
      count: report.count,
      production_by_provider: report.production_by_provider.map { |h|
        { provider: h[:provider], production: h[:production_cents] / 100.0, count: h[:count] }
      },
      production_total: report.production_total_cents / 100.0,
      turnover_by_provider: report.turnover_by_provider.map { |provider, rows|
        {
          provider: provider,
          total: rows.sum(&:total_cents) / 100.0,
          count: rows.size,
          lines: rows.first(300).map { |l|
            { date: l.date&.strftime("%-d %b"), patient: l.patient, tooth: l.tooth, code: l.code,
              description: l.description, units: l.qty, total: l.total_cents / 100.0 }
          },
          truncated: rows.size > 300
        }
      },
      turnover_total: report.turnover_total_cents / 100.0
    }
  end
end

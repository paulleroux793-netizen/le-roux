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

    render inertia: "Reporting", props: {
      kpis: {
        production_month: (Invoice.where(void: false).where("invoice_date >= ?", month_start.to_date).sum(:total_cents) / 100.0),
        collections_month: (Payment.where("received_at >= ?", month_start).sum(:amount_cents) / 100.0),
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
        chair_hours_today: chair_hours_today.round(2)
      },
      production_by_setting: CourseOfTreatment.group(:setting).count,
      invoices_by_status: Invoice.group(:status).count
    }
  end
end

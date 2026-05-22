# Reporting / KPIs (Phase 5.3). Read-only practice metrics. Additive route.
class ReportingController < ApplicationController
  def index
    month_start = Time.current.beginning_of_month
    render inertia: "Reporting", props: {
      kpis: {
        production_month: (Invoice.where(void: false).where("invoice_date >= ?", month_start.to_date).sum(:total_cents) / 100.0),
        collections_month: (Payment.where("received_at >= ?", month_start).sum(:amount_cents) / 100.0),
        outstanding: (Invoice.outstanding.sum("total_cents - paid_cents") / 100.0),
        invoices_total: Invoice.count,
        estimates_open: Estimate.where(status: %w[draft sent]).count,
        courses_open: CourseOfTreatment.open.count,
        imaging_needs_match: ImagingStudy.needs_match.count,
        recalls_due: Recall.where(status: "due").where("due_on <= ?", Date.current).count
      },
      production_by_setting: CourseOfTreatment.group(:setting).count,
      invoices_by_status: Invoice.group(:status).count
    }
  end
end

# Estimates — read-first list (patient quotes built from a course of treatment). Additive route.
class EstimatesController < ApplicationController
  def index
    estimates = Estimate.includes(:patient).order(created_at: :desc).limit(300).to_a
    render inertia: "Estimates", props: {
      estimates: estimates.map { |e|
        {
          id: e.id, number: e.estimate_number, patient_name: e.patient.full_name,
          status: e.status, total: e.total, valid_until: e.valid_until&.iso8601,
          line_count: e.estimate_lines.size
        }
      },
      stats: { total: Estimate.count }
    }
  end
end

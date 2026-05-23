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

  def show
    estimate = Estimate.includes(:patient, estimate_lines: :procedure_code).find(params[:id])
    patient = estimate.patient
    membership = patient.scheme_memberships.first

    render inertia: "EstimateShow", props: {
      estimate: {
        id: estimate.id, number: estimate.estimate_number, status: estimate.status,
        date: estimate.created_at.to_date.iso8601, valid_until: estimate.valid_until&.iso8601,
        medical_total: estimate.medical_total, self_total: estimate.self_total, total: estimate.total,
        visits: estimate.lines_by_visit.map { |visit, lines|
          { visit: visit, lines: lines.map { |l| line_props(l) } }
        }
      },
      practice: practice_props,
      patient: { name: patient.full_name, phone: patient.phone,
                 scheme: membership&.medical_scheme&.name, member_number: membership&.member_number }
    }
  end

  private

  def line_props(l)
    {
      code: l.code, description: l.description, tooth_number: l.tooth_number, quantity: l.quantity,
      icd10_code: l.icd10_code,
      medical: l.medical, self_portion: l.self_portion, line_total: l.line_total
    }
  end

  def practice_props
    p = PracticeBillingProfile.current
    {
      hpcsa: p.hpcsa_number, bhf: p.bhf_practice_number.presence || "— (to be supplied)",
      vat_number: p.vat_number, address: p.address, phone: p.phone, email: p.email,
      bank: "#{p.bank_name} · #{p.bank_account_name} · #{p.bank_account_number} · Branch #{p.bank_branch_code}"
    }
  end
end

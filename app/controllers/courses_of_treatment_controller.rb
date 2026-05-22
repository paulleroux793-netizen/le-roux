# Courses of treatment (the clinical episode). Read-first index + show with odontogram.
# Additive — new route. (Ivory, Phase 2.)
class CoursesOfTreatmentController < ApplicationController
  def index
    cots = CourseOfTreatment.includes(:patient, :treatment_items).order(created_at: :desc).limit(200).to_a
    render inertia: "CoursesOfTreatment", props: {
      courses: cots.map { |c| list_props(c) },
      stats: {
        total: CourseOfTreatment.count,
        open: CourseOfTreatment.open.count
      }
    }
  end

  def show
    cot = CourseOfTreatment.includes(:patient, treatment_items: :procedure_code, clinical_notes: {}).find(params[:id])
    patient = cot.patient

    render inertia: "CourseOfTreatmentShow", props: {
      course: {
        id: cot.id,
        description: cot.description,
        setting: cot.setting,
        status: cot.status,
        authorisation_number: cot.authorisation_number,
        patient: { id: patient.id, name: patient.full_name },
        estimated_total: cot.estimated_total,
        completed_total: cot.completed_total
      },
      items: cot.treatment_items.map { |i|
        {
          id: i.id, code: i.procedure_code&.code, description: i.procedure_code&.description,
          tooth_number: i.tooth_number, surface: i.surface, status: i.status,
          fee: i.fee, completed_date: i.completed_date&.iso8601
        }
      },
      notes: cot.clinical_notes.order(created_at: :desc).map { |n|
        {
          id: n.id, subjective: n.subjective, objective: n.objective,
          assessment: n.assessment, plan: n.plan,
          signed_by: n.signed_by, signed_at: n.signed_at&.iso8601, locked: n.locked
        }
      },
      chart: latest_chart_for(patient)
    }
  end

  private

  def list_props(c)
    {
      id: c.id,
      patient_name: c.patient.full_name,
      description: c.description,
      setting: c.setting,
      status: c.status,
      item_count: c.treatment_items.size,
      # Compute from the already-loaded items (avoids an N+1 SUM per row).
      estimated_total: c.treatment_items.reject { |i| i.status == "voided" }.sum { |i| i.fee_cents.to_i } / 100.0
    }
  end

  # Latest condition per tooth (FDI), for the odontogram.
  def latest_chart_for(patient)
    ToothChartEntry.where(patient_id: patient.id)
      .order(noted_at: :desc)
      .group_by(&:tooth_number)
      .transform_values { |entries| entries.first.condition }
  end
end

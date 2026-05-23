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
      chart: latest_chart_for(patient),
      # P9.3 — props needed by the clickable odontogram modal.
      # `procedure_suggestions` is a condition→code map (bake-in, no fetch).
      # `procedure_codes` lets the user override the suggestion inline.
      procedure_suggestions: ChartingService.suggestions_for_props,
      procedure_codes: ProcedureCode.active.order(:code).pluck(:id, :code, :description)
        .map { |id, code, desc| { id:, code:, description: desc } }
    }
  end

  # P9.3 — POST /courses-of-treatment/chart_quick_add
  #
  # Wired from the odontogram modal. Records a tooth chart entry and
  # (if a procedure code was picked) a planned treatment item on the
  # patient's open COT — auto-creating the COT if none exists.
  # Best-effort; failures bubble up as a redirect_back with alert.
  def chart_quick_add
    patient = Patient.find(params[:patient_id])
    cot, item = ChartingService.add_from_chart(
      patient:           patient,
      tooth_number:      params[:tooth_number],
      condition:         params[:condition],
      procedure_code_id: params[:procedure_code_id]
    )

    expire_dev_page_cache("courses-of-treatment")
    expire_dev_page_cache("patients/show")

    AuditService.log(
      action: "chart.quick_add",
      summary: "Charted tooth #{params[:tooth_number]} as #{params[:condition]}" \
               "#{item ? " + planned #{item.procedure_code.code}" : ''}",
      resource: cot,
      performed_by: audit_performer,
      ip_address: request.remote_ip
    )

    redirect_back fallback_location: course_of_treatment_path(cot),
      notice: "Tooth #{params[:tooth_number]} charted#{item ? ' + procedure planned' : ''}",
      status: :see_other
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    Rails.logger.warn("[CoursesOfTreatmentController#chart_quick_add] #{e.message}")
    redirect_back fallback_location: courses_of_treatment_path,
      alert: "Could not chart tooth: #{e.message}", status: :see_other
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

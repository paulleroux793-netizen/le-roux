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
        .map { |id, code, desc| { id:, code:, description: desc } },
      # C4 — visit-type templates available to apply with one click
      treatment_macros: TreatmentMacro.active.order(:access_code)
        .limit(50).pluck(:id, :access_code, :name)
        .map { |id, code, name| { id:, access_code: code, name: name } }
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

  # R1.2 — POST /courses-of-treatment/:id/add_item
  #
  # Add a procedure to the COT that isn't tied to a specific tooth
  # (oral exam 8101, prophylaxis 8159, x-ray 8107, etc.) — chart_quick_add
  # was tooth-first only and didn't cover these whole-mouth procedures.
  def add_item
    cot = CourseOfTreatment.find(params[:id])
    pc  = ProcedureCode.find(params[:procedure_code_id])

    item = cot.treatment_items.create!(
      procedure_code: pc,
      tooth_number: params[:tooth_number].presence,
      status: "planned"
    )
    AuditService.log(
      action: "treatment_item.added",
      summary: "Added #{pc.code} #{pc.description.to_s.truncate(40)} to COT ##{cot.id}",
      resource: item,
      performed_by: audit_performer,
      ip_address: request.remote_ip
    )
    expire_dev_page_cache("courses-of-treatment")
    redirect_back fallback_location: course_of_treatment_path(cot),
      notice: "Added #{pc.code}", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: course_of_treatment_path(params[:id]),
      alert: e.record.errors.full_messages.to_sentence, status: :see_other
  end

  # C4 — POST /courses-of-treatment/:id/apply_macro
  #
  # Visit-type templates: dentist picks "Recall + Hygiene", "Surgical
  # extraction", "Crown prep visit 1", etc., and the system creates the
  # standard set of planned treatment items in one click. Saves clicks
  # and ensures consistent coding across patients.
  def apply_macro
    cot   = CourseOfTreatment.find(params[:id])
    macro = TreatmentMacro.includes(treatment_macro_items: :procedure_code).find(params[:treatment_macro_id])
    added = 0
    ActiveRecord::Base.transaction do
      macro.treatment_macro_items.each do |mi|
        pc = mi.procedure_code
        next unless pc
        (mi.quantity || 1).times do
          cot.treatment_items.create!(procedure_code: pc, status: "planned")
          added += 1
        end
      end
    end
    AuditService.log(action: "treatment_macro.applied",
                     summary: "Applied macro #{macro.access_code} (#{macro.name}) to COT ##{cot.id} (#{added} items)",
                     resource: cot, performed_by: audit_performer, ip_address: request.remote_ip)
    expire_dev_page_cache("courses-of-treatment")
    redirect_back fallback_location: course_of_treatment_path(cot),
      notice: "Added #{added} item#{added == 1 ? '' : 's'} from \"#{macro.name}\"", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: course_of_treatment_path(params[:id]),
      alert: e.record.errors.full_messages.to_sentence, status: :see_other
  end

  # R1.3a — POST /courses-of-treatment/:id/generate_estimate
  #
  # Build an Estimate from the COT's non-voided items (planned + completed)
  # and redirect to /estimates/:id. Idempotent at the user level — there's
  # no uniqueness constraint, so accidental double-clicks would create two;
  # in practice estimates are infrequent and the latest wins.
  def generate_estimate
    cot = CourseOfTreatment.find(params[:id])
    est = Estimate.from_course(cot)
    est.save!
    AuditService.log(
      action: "estimate.generated",
      summary: "Generated estimate #{est.estimate_number} from COT ##{cot.id} (#{est.estimate_lines.size} lines, R#{format('%.2f', est.total)})",
      resource: est,
      performed_by: audit_performer,
      ip_address: request.remote_ip
    )
    expire_dev_page_cache("estimates")
    redirect_to estimate_path(est), notice: "Estimate #{est.estimate_number} ready", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: course_of_treatment_path(params[:id]),
      alert: e.record.errors.full_messages.to_sentence, status: :see_other
  end

  # R1.3b — POST /courses-of-treatment/:id/generate_invoice
  #
  # Build an Invoice from the COT's COMPLETED items only. If nothing is
  # marked complete yet we friendly-fail rather than creating an empty
  # invoice with sequence-number burnt.
  def generate_invoice
    cot = CourseOfTreatment.find(params[:id])
    if cot.treatment_items.where(status: "completed").none?
      return redirect_back fallback_location: course_of_treatment_path(cot),
        alert: "Mark at least one treatment item Done before invoicing", status: :see_other
    end

    inv = Invoice.from_course(cot)
    inv.save!
    AuditService.log(
      action: "invoice.generated",
      summary: "Generated invoice #{inv.invoice_number} from COT ##{cot.id} (#{inv.invoice_lines.size} lines, R#{format('%.2f', inv.total)})",
      resource: inv,
      performed_by: audit_performer,
      ip_address: request.remote_ip
    )
    expire_dev_page_cache("invoices")
    redirect_to invoice_path(inv), notice: "Invoice #{inv.invoice_number} ready", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: course_of_treatment_path(params[:id]),
      alert: e.record.errors.full_messages.to_sentence, status: :see_other
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

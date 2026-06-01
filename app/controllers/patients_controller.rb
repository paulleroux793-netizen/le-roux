class PatientsController < ApplicationController
  # Client-side DataTable handles search, sort, filter and pagination,
  # so we ship the full patient list (capped for safety). For a single
  # dental practice this is well under a megabyte of JSON.
  LIST_ROW_LIMIT = 500

  # A patient is "Active" if they've had any appointment in the last
  # 6 months OR have an upcoming one. Otherwise "Inactive".
  ACTIVE_WINDOW_MONTHS = 6

  # Curated "base name" dropdown for the New Patient form. Matches the
  # 10 names seeded by db/seeds/medical_schemes.rb. We deliberately do
  # NOT surface the ~168 plan-specific imported records here — the
  # receptionist picks a base scheme, types the membership number,
  # and falls back to "Other" for anything not in the list.
  PICKER_SCHEMES = %w[
    Discovery Bonitas Bestmed GEMS Fedhealth
    Medihelp Medshield Polmed Bankmed Profmed
  ].freeze

  def index
    page_data = dev_page_cache("patients", "index") do
      patients = Patient
        .includes(:appointments, :medical_history)
        .order(:last_name, :first_name)
        .limit(LIST_ROW_LIMIT)
        .to_a

      stats = Rails.cache.fetch("patients/index/stats", expires_in: 30.seconds) do
        {
          total: Patient.count,
          active: Appointment.where("start_time >= ?", ACTIVE_WINDOW_MONTHS.months.ago)
            .distinct
            .count(:patient_id),
          new_this_month: Patient.where(created_at: Time.current.beginning_of_month..).count,
          needs_review: Patient.where(last_name: "(imported)")
            .or(Patient.where(first_name: "Unknown"))
            .or(Patient.where(first_name: "WhatsApp", last_name: "Patient"))
            .or(Patient.where(first_name: "Phone", last_name: "Caller"))
            .count
        }
      end

      {
        patients: patients.map { |p| patient_list_props(p) },
        stats: stats,
        # Common SA schemes for the New Patient form dropdown. Cheap query, no need to cache.
        # Restricted to the curated PICKER_SCHEMES list — the ~168 imported plan-specific
        # records stay in the DB for legacy linkage but never appear in the picker.
        schemes: MedicalScheme.active.where(name: PICKER_SCHEMES).order(:name)
          .pluck(:id, :name).map { |id, name| { id:, name: } }
      }
    end

    render inertia: "Patients", props: page_data
  end

  def show
    page_data = dev_page_cache("patients", "show", params[:id]) do
      patient = Patient.includes(:medical_history).find(params[:id])
      appointments = patient.appointments.order(start_time: :desc).limit(20)
      conversations = patient.conversations.order(updated_at: :desc).limit(10)

      # R2 — quick-action shortcuts: open course of treatment, view
      # outstanding estimates/invoices. We compute these here so the
      # PatientShow toolbar can render their counts without re-fetching.
      open_courses   = CourseOfTreatment.where(patient_id: patient.id)
                                        .where(status: %w[planned active])
                                        .includes(:treatment_items) # item_count below → avoid N+1
                                        .order(created_at: :desc).limit(5).to_a
      open_estimates = Estimate.where(patient_id: patient.id)
                               .where(status: %w[draft sent])
                               .order(created_at: :desc).limit(5).to_a
      open_invoices  = Invoice.where(patient_id: patient.id)
                              .where(status: %w[open part_paid])
                              .order(created_at: :desc).limit(5).to_a
      outstanding_balance_cents = open_invoices.sum { |i| (i.total_cents - i.paid_cents).to_i }

      # Patient-as-spine: the patient page is the single hub for EVERYTHING
      # about this person — treatment plans, estimates, invoices, account.
      # We ship the FULL lists (not just the open ones) so the patient view
      # never has to hand off to a separate top-level Estimates/Invoices/COT
      # screen. Capped for safety; a single patient never has thousands.
      all_courses   = patient.courses_of_treatment.includes(:treatment_items)
                             .order(created_at: :desc).limit(50).to_a
      all_estimates = patient.estimates.order(created_at: :desc).limit(50).to_a
      all_invoices  = patient.invoices.order(created_at: :desc).limit(50).to_a
      all_imaging   = patient.imaging_studies.order(Arel.sql("captured_at DESC NULLS LAST")).limit(50).to_a
      account       = patient.primary_billing_account

      {
        patient: patient_detail_props(patient),
        medical_history: medical_history_props(patient),
        appointments: appointments.map { |a| appointment_props(a) },
        conversations: conversations.map { |c| conversation_props(c) },
        # Full per-patient record sets — the tabs on PatientShow render these inline.
        courses_of_treatment: all_courses.map { |c| course_props(c) },
        estimates: all_estimates.map { |e| estimate_props(e) },
        invoices: all_invoices.map { |i| invoice_props(i) },
        imaging_studies: all_imaging.map { |s| imaging_props(s) },
        billing_account: account && billing_account_props(account),
        account_summary: account_summary(all_invoices),
        # Kept for the at-a-glance shortcut cards on the Overview tab.
        open_courses_of_treatment: open_courses.map { |c|
          { id: c.id, description: c.description, status: c.status, item_count: c.treatment_items.size }
        },
        open_estimates: open_estimates.map { |e|
          { id: e.id, number: e.estimate_number, total: e.total, valid_until: e.valid_until&.iso8601 }
        },
        open_invoices: open_invoices.map { |i|
          { id: i.id, number: i.invoice_number, total: i.total, balance: i.balance }
        },
        outstanding_balance: outstanding_balance_cents / 100.0,
        next_appointment: patient.appointments.upcoming.first&.then { |a|
          { id: a.id, start_time: a.start_time.iso8601, reason: a.reason }
        }
      }
    end

    render inertia: "PatientShow", props: page_data
  end

  # POST /patients
  #
  # Creates a new patient along with (optionally) a nested medical
  # history record. Both succeed or fail together inside a transaction
  # so we never end up with a patient row and an orphaned half-filled
  # medical_history row.
  def create
    result = PatientRegistrationService.new(attributes: patient_params).call
    patient = result.patient

    if result.success?
      # Additive: link a billing account + scheme membership if the form supplied them.
      # Best-effort — never blocks the patient create; errors are logged + flashed.
      begin
        attach_account!(patient, params[:account]) if params[:account].present?
        attach_scheme!(patient,  params[:scheme])  if params[:scheme].present?
      rescue StandardError => e
        Rails.logger.warn("[PatientsController#create] account/scheme link failed: #{e.message}")
      end

      expire_patient_caches!
      NotificationService.patient_created(patient) if result.created?
      AuditService.log(
        action: result.created? ? "patient.created" : "patient.updated",
        summary: "#{result.created? ? 'Created' : 'Updated'} patient record for #{patient.full_name}",
        resource: patient,
        details: { phone: patient.phone, email: patient.email },
        performed_by: audit_performer,
        ip_address: request.remote_ip
      )
      redirect_to patient_path(patient),
        notice: patient_create_notice(result),
        status: :see_other
    else
      redirect_back fallback_location: patients_path,
        alert: patient.errors.full_messages.to_sentence,
        inertia: { errors: inertia_errors_for(patient) },
        status: :see_other
    end
  end

  # PATCH /patients/:id
  #
  # Used by:
  #   - Edit Patient modal (demographics + medical history)
  #   - Medical History panel on PatientShow (medical fields only)
  #
  # Because `accepts_nested_attributes_for :medical_history` is set
  # with `update_only: true`, posting medical_history_attributes will
  # update the existing row or create one if none exists.
  def update
    patient = Patient.find(params[:id])

    if patient.update(patient_params)
      expire_patient_caches!
      AuditService.log(
        action: "patient.updated",
        summary: "Updated patient record for #{patient.full_name}",
        resource: patient,
        details: { phone: patient.phone },
        performed_by: audit_performer,
        ip_address: request.remote_ip
      )
      redirect_back fallback_location: patient_path(patient),
        notice: "Patient updated", status: :see_other
    else
      redirect_back fallback_location: patient_path(patient),
        alert: patient.errors.full_messages.to_sentence,
        inertia: { errors: inertia_errors_for(patient) },
        status: :see_other
    end
  end

  # DELETE /patients/:id
  #
  # Hard-deletes the patient and all associated records.
  # Irreversible — requires explicit confirmation from the UI.
  def destroy
    patient = Patient.find(params[:id])
    name = patient.full_name
    phone = patient.phone

    patient.destroy!

    AuditService.log(
      action: "patient.deleted",
      summary: "Deleted patient record for #{name} (#{phone})",
      details: { name: name, phone: phone },
      performed_by: audit_performer,
      ip_address: request.remote_ip
    )
    expire_patient_caches!

    redirect_to patients_path, notice: "Patient #{name} deleted", status: :see_other
  rescue ActiveRecord::RecordNotFound
    redirect_to patients_path, alert: "Patient not found", status: :see_other
  rescue ActiveRecord::RecordNotDestroyed => e
    redirect_back fallback_location: patients_path,
      alert: "Could not delete patient: #{e.message}", status: :see_other
  end

  private

  # Idempotently link the patient to a BillingAccount based on form params.
  # Creates account on the fly if billing_name supplied; never duplicates.
  def attach_account!(patient, account_params)
    p = account_params.permit(:account_code, :billing_name, :email, :phone).to_h
    return if p["billing_name"].blank?

    account = nil
    if p["account_code"].present?
      account = BillingAccount.find_or_initialize_by(account_code: p["account_code"])
    else
      account = BillingAccount.new(account_code: BillingAccount.next_account_code)
    end
    account.billing_name = p["billing_name"]
    account.email = p["email"].presence if account.respond_to?(:email=)
    account.phone = p["phone"].presence if account.respond_to?(:phone=)
    account.head_patient_id ||= patient.id
    account.save!
    AccountPatient.find_or_create_by!(billing_account: account, patient: patient) { |ap| ap.relationship = "self" }
  end

  # Idempotently link the patient to a scheme membership. Accepts scheme_id (existing
  # MedicalScheme) OR scheme_name (free text, find_or_create_by — the "Other" path).
  def attach_scheme!(patient, scheme_params)
    p = scheme_params.permit(:scheme_id, :scheme_name, :membership_number, :dependant_code).to_h
    return if p["membership_number"].blank?

    scheme =
      if p["scheme_id"].present?
        MedicalScheme.find_by(id: p["scheme_id"])
      elsif p["scheme_name"].present?
        MedicalScheme.find_or_create_by!(name: p["scheme_name"]) { |s| s.active = true }
      end
    return unless scheme

    membership = SchemeMembership.find_or_create_by!(
      medical_scheme_id: scheme.id, member_number: p["membership_number"]
    )
    SchemeMembershipPatient.find_or_create_by!(scheme_membership: membership, patient: patient) do |smp|
      smp.dependant_code = p["dependant_code"].presence
      smp.role = "dependant"
    end
  end

  def patient_params
    permitted = params.require(:patient).permit(
      :first_name, :last_name, :phone, :email, :date_of_birth, :notes, :id_number,
      :ai_consent, # boolean form field → mapped to consent_to_ai_processing_at below
      medical_history_attributes: [
        :id, :allergies, :chronic_conditions, :current_medications,
        :blood_type, :emergency_contact_name, :emergency_contact_phone,
        :insurance_provider, :insurance_policy_number,
        :dental_notes, :last_dental_visit
      ]
    )

    normalized = permitted.to_h

    # POPIA — translate the form's boolean checkbox into the
    # consent_to_ai_processing_at timestamp (and the recorder's name).
    # Ticked → stamp NOW + audit_performer; unticked → clear.
    if normalized.key?("ai_consent")
      flag = ActiveRecord::Type::Boolean.new.cast(normalized.delete("ai_consent"))
      if flag
        normalized["consent_to_ai_processing_at"] ||= Time.current
        normalized["consent_to_ai_processing_by"] ||= audit_performer
      else
        normalized["consent_to_ai_processing_at"] = nil
        normalized["consent_to_ai_processing_by"] = nil
      end
    end
    medical_history = normalized["medical_history_attributes"]
    return normalized unless medical_history.is_a?(Hash)

    cleaned = medical_history.compact_blank
    if cleaned.except("id").empty?
      normalized.delete("medical_history_attributes")
      return normalized
    end

    normalized["medical_history_attributes"] = cleaned
    normalized
  end

  def patient_create_notice(result)
    return "Patient profile completed" if result.upgraded_placeholder?

    "Patient created"
  end

  def inertia_errors_for(record)
    record.errors.to_hash(true).transform_values { |messages| Array(messages).first }
  end

  # Props for the DataTable list — augments the base patient columns
  # with derived fields the screenshot reference shows:
  #   - code: "P001" style id, padded for tidy display
  #   - age: computed from date_of_birth
  #   - status: Active / Inactive based on appointment recency
  #   - next_appointment: nearest upcoming appointment ISO date
  #   - appointment_count: for power-user sorting / filtering
  def patient_list_props(patient)
    now  = Time.current
    all  = patient.appointments
    last_visit = all.select { |a| a.start_time < now }
                    .max_by(&:start_time)
    next_appt  = all.select { |a| a.start_time >= now && a.status.to_s != "cancelled" }
                    .min_by(&:start_time)

    active =
      (last_visit && last_visit.start_time >= ACTIVE_WINDOW_MONTHS.months.ago) ||
      next_appt.present?

    {
      id: patient.id,
      code: "P#{patient.id.to_s.rjust(3, '0')}",
      first_name: patient.first_name,
      last_name: patient.last_name,
      full_name: patient.full_name,
      phone: patient.phone,
      email: patient.email,
      date_of_birth: patient.date_of_birth&.iso8601,
      notes: patient.notes,
      age: age_from(patient.date_of_birth),
      status: active ? "active" : "inactive",
      appointment_count: all.size,
      last_visit: last_visit&.start_time&.iso8601,
      next_appointment: next_appt&.start_time&.iso8601,
      needs_review: patient.needs_review?,
      # Embedded medical history so the Edit-from-list modal has the
      # data without an extra fetch. Hash matches medical_history_props.
      medical_history: medical_history_props(patient)
    }
  end

  def age_from(dob)
    return nil if dob.nil?
    today = Date.current
    age = today.year - dob.year
    age -= 1 if today < dob + age.years
    age
  end

  def patient_detail_props(patient)
    {
      id: patient.id,
      first_name: patient.first_name,
      last_name: patient.last_name,
      full_name: patient.full_name,
      phone: patient.phone,
      email: patient.email,
      date_of_birth: patient.date_of_birth&.iso8601,
      id_number: patient.id_number,
      notes: patient.notes,
      preferred_language: patient.preferred_language,
      created_at: patient.created_at.iso8601,
      # POPIA — AI-processing consent (paper form ticked → flag set)
      ai_consent: patient.ai_consent?,
      ai_consent_at: patient.consent_to_ai_processing_at&.iso8601,
      ai_consent_by: patient.consent_to_ai_processing_by
    }
  end

  # Returns a plain-hash representation of a patient's medical
  # history for the PatientShow / edit modal. Always returns a hash
  # even when no row exists yet, so the React side can render a
  # consistent empty form without null-checks on every field.
  def medical_history_props(patient)
    mh = patient.medical_history
    {
      id: mh&.id,
      allergies: mh&.allergies,
      chronic_conditions: mh&.chronic_conditions,
      current_medications: mh&.current_medications,
      blood_type: mh&.blood_type,
      emergency_contact_name: mh&.emergency_contact_name,
      emergency_contact_phone: mh&.emergency_contact_phone,
      insurance_provider: mh&.insurance_provider,
      insurance_policy_number: mh&.insurance_policy_number,
      dental_notes: mh&.dental_notes,
      last_dental_visit: mh&.last_dental_visit&.iso8601,
      any_data: mh ? mh.any_data? : false,
      blood_types: PatientMedicalHistory::BLOOD_TYPES
    }
  end

  # ── Per-patient hub prop builders ───────────────────────────────────────
  # These feed the tabs on PatientShow so a patient's treatment plans,
  # estimates, invoices and billing account all live under the one record.
  def course_props(c)
    {
      id: c.id,
      description: c.description,
      status: c.status,
      item_count: c.treatment_items.size,
      estimated_total: c.estimated_total,
      completed_total: c.completed_total,
      created_at: c.created_at.iso8601
    }
  end

  def estimate_props(e)
    {
      id: e.id,
      number: e.estimate_number,
      total: e.total,
      status: e.status,
      valid_until: e.valid_until&.iso8601,
      created_at: e.created_at.iso8601
    }
  end

  def invoice_props(i)
    {
      id: i.id,
      number: i.invoice_number,
      total: i.total,
      balance: i.balance,
      status: i.status,
      invoice_date: i.invoice_date&.iso8601,
      created_at: i.created_at.iso8601
    }
  end

  def billing_account_props(account)
    {
      id: account.id,
      account_code: account.account_code,
      billing_name: account.billing_name,
      head_patient_id: account.head_patient_id,
      members: account.patients.map { |p|
        { id: p.id, name: p.full_name, is_head: p.id == account.head_patient_id }
      }
    }
  end

  def imaging_props(s)
    {
      id: s.id,
      modality: s.modality,
      modality_label: s.modality_label,
      captured_at: s.captured_at&.iso8601,
      status: s.status,
      notes: s.notes,
      sidexis_patient_name: s.sidexis_patient_name,
      source_folder: s.source_folder,
      storage_key: s.storage_key
    }
  end

  # Roll-up across all of the patient's invoices for the Account tab.
  def account_summary(invoices)
    billed_cents = invoices.sum { |i| i.total_cents.to_i }
    paid_cents   = invoices.sum { |i| i.paid_cents.to_i }
    {
      total_billed:  billed_cents / 100.0,
      total_paid:    paid_cents / 100.0,
      outstanding:   (billed_cents - paid_cents) / 100.0,
      invoice_count: invoices.size
    }
  end

  def appointment_props(appointment)
    {
      id: appointment.id,
      start_time: appointment.start_time.iso8601,
      end_time: appointment.end_time.iso8601,
      status: appointment.status,
      reason: appointment.reason
    }
  end

  def conversation_props(conversation)
    {
      id: conversation.id,
      channel: conversation.channel,
      status: conversation.status,
      message_count: conversation.messages&.length || 0,
      started_at: conversation.started_at&.iso8601,
      updated_at: conversation.updated_at.iso8601
    }
  end

  def expire_patient_caches!
    expire_dev_page_cache("patients/index")
    expire_dev_page_cache("patients/show")
    Rails.cache.delete("patients/index/stats")
  end
end

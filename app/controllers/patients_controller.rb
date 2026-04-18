class PatientsController < ApplicationController
  # Client-side DataTable handles search, sort, filter and pagination,
  # so we ship the full patient list (capped for safety). For a single
  # dental practice this is well under a megabyte of JSON.
  LIST_ROW_LIMIT = 500

  # A patient is "Active" if they've had any appointment in the last
  # 6 months OR have an upcoming one. Otherwise "Inactive".
  ACTIVE_WINDOW_MONTHS = 6

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
        stats: stats
      }
    end

    render inertia: "Patients", props: page_data
  end

  def show
    page_data = dev_page_cache("patients", "show", params[:id]) do
      patient = Patient.includes(:medical_history).find(params[:id])
      appointments = patient.appointments.order(start_time: :desc).limit(20)
      conversations = patient.conversations.order(updated_at: :desc).limit(10)

      {
        patient: patient_detail_props(patient),
        medical_history: medical_history_props(patient),
        appointments: appointments.map { |a| appointment_props(a) },
        conversations: conversations.map { |c| conversation_props(c) }
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
      expire_patient_caches!
      NotificationService.patient_created(patient) if result.created?
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
      redirect_back fallback_location: patient_path(patient),
        notice: "Patient updated", status: :see_other
    else
      redirect_back fallback_location: patient_path(patient),
        alert: patient.errors.full_messages.to_sentence,
        inertia: { errors: inertia_errors_for(patient) },
        status: :see_other
    end
  end

  private

  def patient_params
    permitted = params.require(:patient).permit(
      :first_name, :last_name, :phone, :email, :date_of_birth, :notes,
      medical_history_attributes: [
        :id, :allergies, :chronic_conditions, :current_medications,
        :blood_type, :emergency_contact_name, :emergency_contact_phone,
        :insurance_provider, :insurance_policy_number,
        :dental_notes, :last_dental_visit
      ]
    )

    normalized = permitted.to_h
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
      notes: patient.notes,
      preferred_language: patient.preferred_language,
      created_at: patient.created_at.iso8601
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

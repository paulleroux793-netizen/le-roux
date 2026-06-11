class PatientsController < ApplicationController
  # Client-side DataTable handles search, sort, filter and pagination,
  # so we ship the FULL patient list (capped for safety). The cap MUST exceed
  # the real patient count or search silently misses everyone past it — at 500
  # a search for "le Roux" (row ~1092, code L00xx) returned No matches because
  # those rows were never shipped. Raised to 5000 to cover the whole practice
  # (~2.5k patients) with headroom, mirroring BillingAccounts. ~2-3MB JSON on a
  # LAN/Tailscale single-practice app — acceptable; revisit with server-side
  # search if the roster ever approaches the cap.
  LIST_ROW_LIMIT = 5000

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

  # Type-ahead patient lookup for the booking modal. Searches name, surname,
  # phone, and the Elixir ACCOUNT CODE across all patients. Returns JSON.
  def lookup
    q = params[:q].to_s.strip
    return render json: { results: [] } if q.length < 2

    pattern = "%#{q.gsub(/[\\%_]/) { |c| "\\#{c}" }}%"
    account_patient_ids = BillingAccount
      .where("account_code ILIKE ?", pattern)
      .joins(:account_patients)
      .pluck("account_patients.patient_id")

    patients = Patient
      .where(
        "first_name ILIKE :p OR last_name ILIKE :p OR " \
        "(first_name || ' ' || last_name) ILIKE :p OR phone ILIKE :p OR id IN (:ids)",
        p: pattern, ids: account_patient_ids.presence || [ 0 ]
      )
      .includes(:billing_accounts)
      .order(:last_name, :first_name)
      .limit(15)

    render json: {
      results: patients.map { |pt|
        { id: pt.id, name: pt.full_name, account_code: pt.account_code, phone: pt.phone }
      }
    }
  end

  def index
    page_data = dev_page_cache("patients", "index") do
      # Organise by ACCOUNT NUMBER (A0001, A0002, …) — Paul's requirement. The
      # alphabetical account code lives on the linked billing account; NULLS LAST
      # so any account-less patients fall to the end.
      patients = Patient
        .left_joins(:billing_accounts)
        .includes(:appointments, :medical_history, :billing_accounts)
        .order(Arel.sql("billing_accounts.account_code ASC NULLS LAST"))
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
        tooth_chart: tooth_chart_for(patient),
        tooth_chart_detail: tooth_chart_detail_for(patient),
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
        },
        google_review_url: PracticeSettings.instance.google_review_url,
        likely_match: likely_match_props(patient)
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
      # Additive: every new patient gets a billing account (surname-initial code); link a
      # scheme membership if the form supplied one. Best-effort — never blocks the create.
      begin
        attach_account!(patient, params[:account])   # always — assigns the next surname-initial code
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
      # Additive (mirrors create): link/refresh a billing account + scheme if the edit form
      # supplied them — so reception CAN add a billing account to an existing patient (previously
      # only possible at create time, leaving account-less patients with no statements). Best-effort.
      begin
        attach_account!(patient, params[:account]) if params[:account].present?
        attach_scheme!(patient,  params[:scheme])  if params[:scheme].present?
      rescue StandardError => e
        Rails.logger.warn("[PatientsController#update] account/scheme link failed: #{e.message}")
      end
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

  # POST /patients/:id/merge_into  { target_id }
  # Reception's audited merge of a self-registered placeholder INTO an existing patient.
  def merge_into
    placeholder = Patient.find(params[:id])
    target      = Patient.find(params[:target_id])
    PatientMerge.call(placeholder: placeholder, target: target)
    AuditService.log(
      action: "patient.merged",
      summary: "Merged self-registration '#{placeholder.full_name}' into #{target.full_name}",
      resource: target, details: { merged_from: placeholder.id },
      performed_by: audit_performer, ip_address: request.remote_ip
    )
    expire_patient_caches!
    redirect_to patient_path(target), notice: "Merged into #{target.full_name}.", status: :see_other
  rescue StandardError => e
    redirect_back fallback_location: patient_path(params[:id]),
      alert: "Merge failed: #{e.message}", status: :see_other
  end

  # POST /patients/:id/confirm_new
  # Reception confirms a self-registration is genuinely NEW: clear the review flag, give them an
  # account (surname-initial) and record consent (the intake form is signed).
  def confirm_new
    patient = Patient.find(params[:id])
    patient.update!(notes: patient.notes.to_s.sub(Patient::SELF_REG_MARKER, "").strip.presence)
    PatientMerge.ensure_account!(patient)
    if patient.consent_to_ai_processing_at.blank?
      patient.update!(consent_to_ai_processing_at: Time.current, consent_to_ai_processing_by: "Online intake form (signed)")
    end
    expire_patient_caches!
    redirect_to patient_path(patient),
      notice: "Confirmed as a new patient (account #{patient.account_code}).", status: :see_other
  rescue StandardError => e
    redirect_back fallback_location: patient_path(params[:id]),
      alert: "Could not confirm: #{e.message}", status: :see_other
  end

  private

  # Reception-only: the existing patient this self-registration most likely already is (by
  # id_number, then phone, then name). Powers the "Merge into…" banner. nil unless under review.
  def likely_match_props(patient)
    return nil unless patient.needs_review?
    m   = (Patient.where.not(id: patient.id).find_by(id_number: patient.id_number) if patient.id_number.present?)
    m ||= (Patient.where.not(id: patient.id).where(phone: patient.phone).first if patient.phone.present?)
    m ||= Patient.where.not(id: patient.id)
                 .where("LOWER(first_name) = ? AND LOWER(last_name) = ?",
                        patient.first_name.to_s.downcase, patient.last_name.to_s.downcase).first
    m && { id: m.id, name: m.full_name, account_code: m.account_code }
  rescue StandardError
    nil
  end

  # Idempotently link the patient to a BillingAccount. Every patient gets an account: if the
  # form supplies an existing account_code we link to it (family members share one account),
  # otherwise we open a new account whose code follows the surname-initial scheme. Never duplicates.
  def attach_account!(patient, account_params)
    p = (account_params || ActionController::Parameters.new).permit(:account_code, :billing_name, :email, :phone).to_h
    return if patient.account_patients.exists? && p["account_code"].blank? # already has an account

    account = nil
    if p["account_code"].present?
      account = BillingAccount.find_or_initialize_by(account_code: p["account_code"])
    else
      account = BillingAccount.new(account_code: BillingAccount.next_account_code(patient.last_name))
    end
    account.billing_name = p["billing_name"].presence || patient.full_name
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
      code: patient.account_code.presence || "P#{patient.id.to_s.rjust(3, '0')}",
      first_name: patient.first_name,
      last_name: patient.last_name,
      full_name: patient.full_name,
      phone: patient.display_phone,
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
  # Dental chart overlay for the patient profile (Paul 2026-06-07): a per-tooth status map for
  # the Odontogram — RED ("needs_work") = outstanding work (planned treatment items + teeth
  # marked extraction_planned); BLACK ("done") = work done/existing (completed items + existing
  # restorations). needs_work wins over done when a tooth has both. Read-only; FDI keys are strings.
  def tooth_chart_for(patient)
    done_conditions = %w[filling crown bridge implant root_canal]
    latest = {}
    ToothChartEntry.current_for(patient).each { |e| latest[e.tooth_number.to_s] ||= e.condition }
    items = TreatmentItem.where(course_of_treatment_id: patient.courses_of_treatment.select(:id))
                         .where.not(tooth_number: [ nil, "" ])
    chart = {}
    latest.each { |t, c| chart[t] = "done" if done_conditions.include?(c) }
    items.where(status: "completed").pluck(:tooth_number).each { |t| chart[t.to_s] = "done" }
    latest.each { |t, c| chart[t] = "needs_work" if c == "extraction_planned" }
    items.where(status: "planned").pluck(:tooth_number).each { |t| chart[t.to_s] = "needs_work" }
    chart
  end

  # Per-tooth list of PLANNED procedures (the outstanding/red work) so the chart can show a
  # tooltip — e.g. "16" => "Crown - porcelain/ceramic; Root canal therapy". Read-only.
  def tooth_chart_detail_for(patient)
    TreatmentItem.where(course_of_treatment_id: patient.courses_of_treatment.select(:id), status: "planned")
                 .where.not(tooth_number: [ nil, "" ]).includes(:procedure_code)
                 .group_by { |i| i.tooth_number.to_s }
                 .transform_values { |its| its.filter_map { |i| i.procedure_code&.description }.uniq.join("; ").presence }
                 .compact
  end

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
      title: estimate_display_title(e),
      number: e.estimate_number,
      total: e.total,
      status: e.status,
      valid_until: e.valid_until&.iso8601,
      created_at: e.created_at.iso8601
    }
  end

  # An estimate should read as its TREATMENT, not its EST number (Paul, 2026-06-05).
  # Prefer the procedure-line description; else the notes (Elixir treatment text,
  # minus our [elixir] import tag); else a sensible fallback.
  # Elixir process-status prefixes to drop so the title is just the treatment
  # (Paul: don't show "Cost Acceptance" etc.).
  ESTIMATE_PREFIXES = /\A(cost acceptance|treatment planning|treatment plan|cost estimate|quotation|quote|estimate|proforma|pro forma|open)\b[\s:.-]*/i

  def estimate_display_title(e)
    line = e.estimate_lines.first&.description.presence
    raw  = line || e.notes.to_s.sub(/\A\[elixir\]\s*/i, "").strip
    raw  = raw.sub(ESTIMATE_PREFIXES, "").strip while raw =~ ESTIMATE_PREFIXES
    return "Estimate" if raw.blank?
    raw == raw.upcase ? raw.titleize : raw
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
      storage_key: s.storage_key,
      has_image: s.storage_key.present?
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

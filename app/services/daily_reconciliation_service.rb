# Daily Reconciliation — the learning-loop service.
#
# For one date, computes a side-by-side picture of:
#   * What Elixir actually delivered (from elixir_*_snapshots)
#   * What Ivory has captured for the same day (appointments + scribe sessions + invoices)
#   * The gap, expressed as ACTIONABLE improvement suggestions
#
# This is Paul's explicit ask (2026-05-27):
#   "Compare Elixir-actual vs Ivory-predicted. What improvements can we make
#   to Ivory so it can also get that result?"
#
# The output is a Hash ready to render in the Reconciliation Inertia page.
#
# Improvement-suggestion categories
# --------------------------------
# missing_procedure_code   — code billed in Elixir but absent from Ivory's catalogue
# stale_procedure_price    — code billed at a price different to Ivory's catalogue
# new_account              — patient billed by Elixir not in Ivory's patient table
# scribe_did_not_capture   — patient was in Elixir today but Ivory's scribe has no transcript
# transcript_no_summary    — Ivory has the transcript but never ran the AI summary
# estimate_value_mismatch  — Ivory's draft estimate differs >R200 from Elixir's billed total
# code_keyword_miss        — code billed but ScribeDraftService keyword map doesn't suggest it
class DailyReconciliationService
  attr_reader :date, :data

  def initialize(date = Date.current)
    @date = date
    @data = nil
  end

  def call
    @data = {
      date: @date.iso8601,
      pretty_date: @date.strftime("%A %-d %B %Y"),
      elixir_totals: elixir_totals,
      ivory_totals:  ivory_totals,
      delta:         deltas,
      patient_rows:  patient_rows,
      improvements:  improvement_suggestions,
      generated_at:  Time.current.iso8601
    }
    self
  end

  def to_h
    @data
  end

  private

  # ── Aggregate totals ────────────────────────────────────────────────────
  def elixir_totals
    txns_for_day = ElixirTransactionSnapshot.for_date(@date)
    billed_total = txns_for_day.procedures_only.sum(:debit)
    received     = txns_for_day.payments_only.sum(:credit)
    diary_rows   = ElixirDiarySnapshot.for_date(@date)
    {
      billed_zar:    money(billed_total),
      received_zar:  money(received),
      diary_slots:   diary_rows.count,
      new_patients:  diary_rows.where(is_new_patient: true).count,
      procedures_billed: txns_for_day.procedures_only.count,
      unique_patients:  txns_for_day.procedures_only.distinct.count(:account_code),
      providers:        txns_for_day.procedures_only.distinct.pluck(:dentist).compact
    }
  end

  def ivory_totals
    appts = Appointment.where(start_time: @date.beginning_of_day..@date.end_of_day)
    completed = appts.where(status: %i[completed in_consultation])
    invoices_today = Invoice.where(invoice_date: @date)
    invoiced_total_cents = invoices_today.sum(:total_cents)
    {
      appointments_today: appts.count,
      completed:          completed.count,
      with_scribe:        completed.joins("LEFT JOIN scribe_sessions s ON s.appointment_id = appointments.id")
                                    .where("s.id IS NOT NULL").distinct.count,
      with_summary:       completed.where.not(summary_generated_at: nil).count,
      invoiced_zar:       money(BigDecimal(invoiced_total_cents.to_s) / 100),
      consent_on:         Patient.joins(:appointments)
                                  .where(appointments: { start_time: @date.beginning_of_day..@date.end_of_day })
                                  .where.not(consent_to_ai_processing_at: nil)
                                  .distinct.count
    }
  end

  def deltas
    e = elixir_totals; i = ivory_totals
    {
      billed_vs_invoiced_zar: money(e[:billed_zar].to_d - i[:invoiced_zar].to_d),
      diary_vs_appts:         e[:diary_slots] - i[:appointments_today],
      scribe_coverage_pct:    pct_or_zero(i[:with_scribe], i[:appointments_today]),
      summary_coverage_pct:   pct_or_zero(i[:with_summary], i[:with_scribe]),
      consent_coverage_pct:   pct_or_zero(i[:consent_on], i[:appointments_today])
    }
  end

  # ── Per-patient rows ───────────────────────────────────────────────────
  # One row per Elixir billing account (the patient/family unit). Includes
  # the matching Ivory appointment + scribe summary + invoice if we can
  # join them (by name OR by billing_account.account_code).
  def patient_rows
    by_account = ElixirTransactionSnapshot.for_date(@date).procedures_only
                  .order(:transaction_date, :account_code)
                  .group_by(&:account_code)

    by_account.map do |account_code, lines|
      payment_lines = ElixirTransactionSnapshot.for_date(@date).payments_only.where(account_code: account_code)

      patient_name = lines.first.patient_surname
      ivory_appt   = match_ivory_appointment(name: patient_name, account_code: account_code, on_date: @date)
      scribe       = ivory_appt && ScribeSession.where(appointment_id: ivory_appt.id).order(:created_at).last

      {
        account_code:     account_code,
        patient_name:     patient_name,
        dependant:        lines.first.dependant_name,
        billed_zar:       money(lines.sum(&:debit)),
        paid_zar:         money(payment_lines.sum(&:credit)),
        codes:            lines.map { |l| { code: l.procedure_code, tooth: l.tooth, debit: money(l.debit), units: l.units } },
        ivory_match: {
          appointment_id: ivory_appt&.id,
          status:         ivory_appt&.status,
          has_scribe:     !!scribe,
          has_summary:    !!ivory_appt&.summary_generated_at,
          decisions:      ivory_appt&.summary_decisions_text&.slice(0, 200),
          estimate_intent: ivory_appt&.summary_estimate_intent_text&.slice(0, 200),
          predicted_estimate_zar: predicted_estimate_for(scribe&.transcript)
        }
      }
    end
  end

  # Loose join: try account_code first, then patient surname-LIKE.
  def match_ivory_appointment(name:, account_code:, on_date:)
    return nil if on_date.nil?
    by_account = nil
    if account_code.present?
      ba = BillingAccount.find_by(account_code: account_code)
      if ba && ba.respond_to?(:patients)
        patient_ids = ba.patients.pluck(:id)
        by_account = Appointment.where(patient_id: patient_ids,
                                       start_time: on_date.beginning_of_day..on_date.end_of_day).first
        return by_account if by_account
      end
    end
    return nil if name.blank?

    # Elixir uses "SURNAME,I MR/MRS" → use just the surname token
    surname = name.split(",").first.to_s.strip
    return nil if surname.empty?

    Appointment.joins(:patient)
               .where("LOWER(patients.last_name) = LOWER(?) OR LOWER(patients.first_name) LIKE LOWER(?)",
                      surname, "%#{surname}%")
               .where(start_time: on_date.beginning_of_day..on_date.end_of_day)
               .first
  end

  # Stub for now — relies on ScribeDraftService later. Empty string means
  # "no prediction available" (rather than R0). We deliberately don't
  # invent a number Ivory doesn't actually have.
  def predicted_estimate_for(transcript)
    return nil if transcript.blank?
    findings = begin
      ScribeDraftService.new(transcript).extract
    rescue StandardError
      []
    end
    return nil if findings.empty?
    sum = findings.sum do |f|
      next 0 if f["code"].blank?
      cents = ProcedureCode.find_by(code: f["code"])&.default_fee_cents || 0
      BigDecimal(cents.to_s) / 100
    end
    money(sum)
  end

  # ── Improvement suggestions ─────────────────────────────────────────────
  def improvement_suggestions
    suggestions = []
    suggestions.concat missing_procedure_codes
    suggestions.concat stale_procedure_prices
    suggestions.concat scribe_gaps
    suggestions.concat summary_gaps
    suggestions.concat estimate_mismatches
    suggestions.concat code_keyword_misses
    suggestions
  end

  def missing_procedure_codes
    codes_today = ElixirTransactionSnapshot.for_date(@date).procedures_only.pluck(:procedure_code).uniq
    in_catalogue = ProcedureCode.where(code: codes_today).pluck(:code)
    missing = codes_today - in_catalogue
    missing.map do |code|
      sample = ElixirTransactionSnapshot.for_date(@date).find_by(procedure_code: code)
      {
        kind: "missing_procedure_code",
        severity: "high",
        title: "Add procedure code #{code} to Ivory's catalogue",
        detail: "Elixir billed code #{code} today (R#{money(sample.debit)}) for account #{sample.account_code}. " \
                "Ivory doesn't know about it — every future scribe draft that should suggest #{code} will silently skip it.",
        action: { type: "create_procedure_code", code: code, suggested_fee: money(sample.debit) }
      }
    end
  end

  def stale_procedure_prices
    codes_today = ElixirTransactionSnapshot.for_date(@date).procedures_only
    grouped = codes_today.group(:procedure_code).pluck(:procedure_code, "AVG(debit)::numeric")
    grouped.flat_map do |code, avg_debit|
      cat = ProcedureCode.find_by(code: code)
      next [] unless cat
      next [] if cat.default_fee_cents.nil? || cat.default_fee_cents.to_i == 0
      cat_fee = BigDecimal(cat.default_fee_cents.to_s) / 100
      diff = (BigDecimal(avg_debit.to_s) - cat_fee).abs
      next [] if diff < 5      # ignore noise of cents
      [{
        kind: "stale_procedure_price",
        severity: diff > 100 ? "high" : "medium",
        title: "Update procedure code #{code} fee",
        detail: "Elixir billed code #{code} at avg R#{money(avg_debit)} today. " \
                "Ivory's catalogue has R#{money(cat_fee)}. Delta R#{money(diff)}.",
        action: { type: "update_procedure_code_fee", code: code, suggested_fee: money(avg_debit) }
      }]
    end
  end

  def scribe_gaps
    # Appointments that completed today but have no scribe session
    completed_today = Appointment.where(start_time: @date.beginning_of_day..@date.end_of_day,
                                         status: %i[completed in_consultation])
    appt_ids_with_scribe = ScribeSession.where(appointment_id: completed_today.select(:id)).pluck(:appointment_id).uniq
    no_scribe = completed_today.where.not(id: appt_ids_with_scribe).preload(:patient).limit(20)
    no_scribe.map do |a|
      {
        kind: "scribe_did_not_capture",
        severity: "medium",
        title: "Scribe missed appointment ##{a.id} (#{a.patient&.full_name})",
        detail: "Appointment ran #{a.start_time.strftime('%H:%M')}–#{a.end_time.strftime('%H:%M')} but no ScribeSession was created. " \
                "Possible causes: surgery PC mic disconnected, daemon crashed, or status wasn't moved to in_consultation in time.",
        action: { type: "investigate_recording_device", appointment_id: a.id }
      }
    end
  end

  def summary_gaps
    with_scribe_no_summary = Appointment
                              .joins("INNER JOIN scribe_sessions s ON s.appointment_id = appointments.id")
                              .where(start_time: @date.beginning_of_day..@date.end_of_day)
                              .where(summary_generated_at: nil)
                              .where.not("LENGTH(COALESCE(s.transcript, '')) = 0")
                              .preload(:patient).limit(20)
    with_scribe_no_summary.map do |a|
      {
        kind: "transcript_no_summary",
        severity: "low",
        title: "Generate summary for appointment ##{a.id} (#{a.patient&.full_name})",
        detail: "Transcript exists but AppointmentSummaryService hasn't been called. " \
                "Possible: appointment never moved to 'completed', LLM call failed, or ANTHROPIC_API_KEY missing.",
        action: { type: "run_summary", appointment_id: a.id }
      }
    end
  end

  def estimate_mismatches
    suggestions = []
    patient_rows.each do |row|
      pred = row.dig(:ivory_match, :predicted_estimate_zar)
      actual = row[:billed_zar]
      next if pred.nil? || actual.nil?
      delta = (pred.to_d - actual.to_d).abs
      next if delta < 200
      suggestions << {
        kind: "estimate_value_mismatch",
        severity: delta > 1000 ? "high" : "medium",
        title: "Estimate gap on #{row[:patient_name]} (#{row[:account_code]}) — Ivory R#{pred}, Elixir R#{actual}",
        detail: "Difference: R#{money(delta)}. Ivory's predicted estimate from the scribe transcript was R#{pred}; " \
                "reception actually billed R#{actual}. Review the transcript vs the billed codes to find the gap.",
        action: { type: "review_appointment", appointment_id: row.dig(:ivory_match, :appointment_id) }
      }
    end
    suggestions
  end

  # Codes billed today that ScribeDraftService's keyword map doesn't surface
  # Useful for expanding the regex map in scribe_draft_service.rb
  def code_keyword_misses
    return [] unless defined?(ScribeDraftService)
    keyword_codes = ScribeDraftService.const_get(:KEYWORD_CODES).values.uniq
    billed_today = ElixirTransactionSnapshot.for_date(@date).procedures_only.pluck(:procedure_code).uniq
    misses = billed_today - keyword_codes - ScribeDraftService.const_get(:KEYWORD_CODES).values
    misses.uniq.take(10).map do |code|
      cat = ProcedureCode.find_by(code: code)
      {
        kind: "code_keyword_miss",
        severity: "low",
        title: "ScribeDraftService never suggests #{code} (#{cat&.description || 'no description'})",
        detail: "Code #{code} was billed today but isn't in the keyword→code map. Add a regex entry to surface it " \
                "from future transcripts. Look at the actual transcripts containing this billed code today to choose the right trigger words.",
        action: { type: "add_keyword_mapping", code: code }
      }
    end
  rescue StandardError
    []
  end

  # ── Helpers ─────────────────────────────────────────────────────────────
  def money(v)
    return "0.00" if v.nil?
    sprintf("%.2f", v.to_d).delete(",")
  end

  def pct_or_zero(num, denom)
    return 0 if denom.to_i.zero?
    ((num.to_f / denom.to_f) * 100).round(1)
  end
end

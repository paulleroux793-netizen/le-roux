# Estimates — read-first list (patient quotes built from a course of treatment). Additive route.
require "csv"

class EstimatesController < ApplicationController
  include VisitSuggestions
  def index
    # eager-load estimate_lines (size) + billing_account (account code) — else N+1.
    estimates = Estimate.includes(:patient, :estimate_lines, :billing_account).order(created_at: :desc).limit(500).to_a

    # Estimates TRACKER lifecycle colour (Paul 2026-06-07): GREEN = treatment done (accepted, OR
    # the linked course-of-treatment's items are ALL completed); BLUE = not done but the patient has
    # a future booked appointment; YELLOW = outstanding (not done, nothing booked). All batched (no N+1).
    booked = Appointment.where(patient_id: estimates.map(&:patient_id).uniq)
                        .where("start_time > ?", Time.current).where.not(status: "cancelled")
                        .distinct.pluck(:patient_id).to_set

    # COTs whose every treatment item is completed → the treatment actually happened.
    cot_ids   = estimates.filter_map(&:course_of_treatment_id).uniq
    total_ct  = TreatmentItem.where(course_of_treatment_id: cot_ids).group(:course_of_treatment_id).count
    done_ct   = TreatmentItem.where(course_of_treatment_id: cot_ids, status: "completed").group(:course_of_treatment_id).count
    cot_done  = cot_ids.select { |id| total_ct[id].to_i.positive? && total_ct[id] == done_ct[id] }.to_set

    rows = estimates.map { |e|
      done = e.status == "accepted" || (e.course_of_treatment_id && cot_done.include?(e.course_of_treatment_id))
      colour = if done then "green"
      elsif booked.include?(e.patient_id) then "blue"
      else "yellow"
      end
      aged = colour == "yellow" && e.created_at < 30.days.ago # outstanding > 30 days = chase-list
      details = if e.estimate_lines.any?
        e.estimate_lines.map(&:description).compact_blank.first(3).join("; ")
      else
        e.notes.to_s.gsub(/\[[a-z]+\]/i, "").strip
      end
      {
        id: e.id, number: e.estimate_number, patient_name: e.patient.full_name, patient_id: e.patient_id,
        account_code: e.billing_account&.account_code,
        status: e.status, status_colour: colour,
        date_sent: e.created_at.to_date.iso8601,
        last_activity: e.updated_at.iso8601, aged: aged,
        details: details.presence, provider_name: e.provider_name,
        total: e.total, valid_until: e.valid_until&.iso8601,
        line_count: e.estimate_lines.size
      }
    }.sort_by { |r| r[:last_activity] }.reverse # most recently active first

    respond_to do |format|
      format.html do
        render inertia: "Estimates", props: {
          estimates: rows,
          stats: {
            total: Estimate.count,
            outstanding: rows.count { |r| r[:status_colour] == "yellow" },
            booked: rows.count { |r| r[:status_colour] == "blue" },
            done: rows.count { |r| r[:status_colour] == "green" },
            # Pipeline value per state — reception wants "R X outstanding in un-accepted estimates".
            outstanding_value: rows.select { |r| r[:status_colour] == "yellow" }.sum { |r| r[:total].to_f },
            booked_value: rows.select { |r| r[:status_colour] == "blue" }.sum { |r| r[:total].to_f },
            done_value: rows.select { |r| r[:status_colour] == "green" }.sum { |r| r[:total].to_f },
            # Aged chase-list: outstanding estimates older than 30 days (overdue follow-ups).
            aged: rows.count { |r| r[:aged] },
            aged_value: rows.select { |r| r[:aged] }.sum { |r| r[:total].to_f }
          }
        }
      end
      # Reception export — the tracker as a spreadsheet (mirrors the manual 'Estimates listing.xlsx').
      format.csv do
        labels = { "green" => "Done", "blue" => "Booked", "yellow" => "Outstanding" }
        csv = CSV.generate(headers: true) do |out|
          out << [ "Status", "Number", "Patient", "Account", "Date sent", "Last activity", "Treatment", "Dr", "Value" ]
          rows.each do |r|
            out << [ labels[r[:status_colour]], r[:number], r[:patient_name], r[:account_code],
                     r[:date_sent], r[:last_activity]&.first(10), r[:details], r[:provider_name],
                     format("%.2f", r[:total].to_f) ]
          end
        end
        send_data csv, filename: "estimates-tracker-#{Date.current.iso8601}.csv", type: "text/csv"
      end
    end
  end

  # POST /patients/:patient_id/estimates — start a fresh blank draft estimate for a
  # patient (reception/dentist quoting flow), then drop into the editor to add lines.
  def create
    patient = Patient.find(params[:patient_id])
    as_invoice = params[:intent].to_s == "invoice" # same editor; finalises as an invoice instead of a quote
    estimate = Estimate.create!(
      patient: patient,
      billing_account: patient.billing_accounts.first,
      status: "draft",
      subtotal_cents: 0, vat_cents: 0, total_cents: 0
    )
    AuditService.log(
      action: "estimate.created",
      summary: "Started a new #{as_invoice ? 'invoice' : 'estimate'} for #{patient.full_name}",
      resource: estimate,
      performed_by: audit_performer,
      ip_address: request.remote_ip
    )
    redirect_to estimate_path(estimate, (as_invoice ? { intent: "invoice" } : {})),
      notice: "New #{as_invoice ? 'invoice' : 'estimate'} started — describe the treatment or add codes below.", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: patient_path(params[:patient_id]),
      alert: "Could not start estimate: #{e.record.errors.full_messages.to_sentence}", status: :see_other
  end

  # PATCH /estimates/:id — set the treating dentist on the estimate so it carries
  # through to the invoice on conversion (cycle 22). Provider name is uppercased
  # to match the invoice/statement convention.
  def update
    estimate = Estimate.find(params[:id])
    estimate.update!(provider_name: params[:provider_name].to_s.upcase.presence)
    redirect_to estimate_path(estimate), notice: "Treating dentist updated", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: estimate_path(params[:id]),
      alert: e.record.errors.full_messages.to_sentence, status: :see_other
  end

  def show
    estimate = Estimate.includes(estimate_lines: :procedure_code,
                                  patient: { scheme_memberships: :medical_scheme }).find(params[:id])
    patient = estimate.patient
    membership = patient.scheme_memberships.first

    # P9.5 — server-rendered PDF for download / WhatsApp send. Pure Ruby (Prawn).
    respond_to do |format|
      format.html { render_inertia(estimate, patient, membership) }
      format.pdf do
        AuditService.log(
          action: "estimate.pdf_downloaded",
          summary: "Downloaded estimate #{estimate.estimate_number}",
          resource: estimate,
          performed_by: audit_performer,
          ip_address: request.remote_ip
        )
        send_data DocumentPdf.estimate(estimate),
          filename: "#{estimate.estimate_number}.pdf",
          type: "application/pdf",
          disposition: "inline"
      end
    end
  end

  # C1 — POST /estimates/:id/upload_attachment
  #
  # Reception or dentist drag-drops an X-ray screenshot / photo / PDF onto
  # the EstimateShow page. Stored via ActiveStorage; surfaces inline.
  def upload_attachment
    estimate = Estimate.find(params[:id])
    file = params[:file]
    if file.blank?
      return redirect_back fallback_location: estimate_path(estimate),
        alert: "No file provided", status: :see_other
    end
    estimate.attachments.attach(file)
    AuditService.log(action: "estimate.attachment_added",
                     summary: "Attached #{file.original_filename} to #{estimate.estimate_number}",
                     resource: estimate, performed_by: audit_performer, ip_address: request.remote_ip)
    redirect_back fallback_location: estimate_path(estimate),
      notice: "Attached #{file.original_filename}", status: :see_other
  end

  def delete_attachment
    estimate = Estimate.find(params[:id])
    blob = estimate.attachments.find_by(id: params[:attachment_id])
    if blob
      blob.purge
      AuditService.log(action: "estimate.attachment_removed",
                       summary: "Removed attachment from #{estimate.estimate_number}",
                       resource: estimate, performed_by: audit_performer, ip_address: request.remote_ip)
    end
    redirect_back fallback_location: estimate_path(estimate),
      notice: "Attachment removed", status: :see_other
  end

  # R1.4 — POST /estimates/:id/accept_and_invoice
  #
  # Patient accepts the quote → convert to a real invoice in one click.
  # Model owns the transaction; we add audit + redirect.
  def accept_and_invoice
    estimate = Estimate.find(params[:id])
    if estimate.status == "accepted"
      return redirect_to estimate_path(estimate),
        alert: "Already accepted — find the invoice in /invoices", status: :see_other
    end
    if estimate.estimate_lines.empty?
      return redirect_to estimate_path(estimate),
        alert: "Add at least one line before converting this estimate to an invoice", status: :see_other
    end

    invoice = estimate.accept_and_invoice!
    AuditService.log(
      action: "estimate.accepted",
      summary: "Patient accepted estimate #{estimate.estimate_number} → invoice #{invoice.invoice_number} (R#{format('%.2f', invoice.total)})",
      resource: invoice,
      details: { estimate_id: estimate.id, invoice_id: invoice.id },
      performed_by: audit_performer,
      ip_address: request.remote_ip
    )
    expire_dev_page_cache("estimates")
    expire_dev_page_cache("invoices")
    redirect_to invoice_path(invoice),
      notice: "Estimate accepted — invoice #{invoice.invoice_number} created", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: estimate_path(params[:id]),
      alert: e.record.errors.full_messages.to_sentence, status: :see_other
  end

  # Add every item from a visit-bundle macro (e.g. "New patient exam") to this
  # estimate as lines in one click — the same time-saver the treatment plan has.
  def apply_macro
    estimate = Estimate.find(params[:id])
    macro = TreatmentMacro.includes(treatment_macro_items: :procedure_code).find(params[:treatment_macro_id])
    added = 0
    ActiveRecord::Base.transaction do
      macro.treatment_macro_items.each do |mi|
        pc = mi.procedure_code
        next unless pc
        estimate.estimate_lines.create!(
          procedure_code: pc, code: pc.code, description: pc.description,
          quantity: [ mi.quantity.to_i, 1 ].max,
          vat_treatment: pc.vat_treatment.presence || "standard",
          unit_fee_cents: pc.default_fee_cents.to_i
        )
        added += 1
      end
      estimate.estimate_lines.reload
      estimate.recalculate
      estimate.save!
    end
    AuditService.log(action: "estimate.macro_applied",
                     summary: "Applied macro #{macro.access_code} (#{macro.name}) to estimate #{estimate.estimate_number} (#{added} lines)",
                     resource: estimate, performed_by: audit_performer, ip_address: request.remote_ip)
    expire_dev_page_cache("estimates")
    redirect_back fallback_location: estimate_path(estimate),
      notice: "Added #{added} line#{added == 1 ? '' : 's'} from \"#{macro.name}\"", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: estimate_path(params[:id]),
      alert: e.record.errors.full_messages.to_sentence, status: :see_other
  end

  # POST /estimates/:id/ai_compose — free-text treatment → auto-populated coded lines.
  # The AI maps to the practice's own catalogue + bundles, one line per tooth; staff adjust after.
  def ai_compose
    estimate = Estimate.find(params[:id])
    return redirect_to(estimate_path(estimate), alert: "Describe the treatment first.", status: :see_other) if params[:prompt].to_s.strip.blank?

    result = AiService.new.compose_treatment_lines(params[:prompt])
    added = 0
    ActiveRecord::Base.transaction do
      Array(result["lines"]).each do |l|
        pc = ProcedureCode.find_by(code: l["code"].to_s)
        next unless pc

        estimate.estimate_lines.create!(
          procedure_code_id: pc.id, code: pc.code, description: pc.description,
          tooth_number: l["tooth_number"].presence,
          quantity: [ l["quantity"].to_i, 1 ].max,
          unit_fee_cents: pc.default_fee_cents.to_i,
          vat_treatment: (pc.vat_treatment.presence || "standard"),
          icd10_code: l["icd10"].presence,
          source: "ai" # edit-rate signal: track whether AI-added lines survive to acceptance
        )
        added += 1
      end
      estimate.estimate_lines.reload
      estimate.recalculate
      estimate.save!
      # Persist the AI's guidance so it shows on the estimate (not just a one-shot flash).
      estimate.update!(ai_note: result["notes"].presence)
    end

    AuditService.log(action: "estimate.ai_compose",
      summary: "AI auto-populated #{added} line(s) on #{estimate.estimate_number} from: #{params[:prompt].to_s[0, 80]}",
      resource: estimate, performed_by: audit_performer, ip_address: request.remote_ip) if defined?(AuditService)

    if added.positive?
      note = result["notes"].present? ? " AI note: #{result['notes'].to_s[0, 140]}" : ""
      redirect_to estimate_path(estimate), notice: "Added #{added} line#{added == 1 ? '' : 's'} — please review & adjust.#{note}", status: :see_other
    else
      redirect_to estimate_path(estimate), alert: "Couldn't map that to codes (#{result['error'] || 'no match'}) — rephrase or add manually.", status: :see_other
    end
  end

  private

  # Inertia render — extracted so the .html branch above stays a one-liner.
  def render_inertia(estimate, patient, membership)
    # PREDICTIVE (shared VisitSuggestions concern): from the patient's next appointment
    # reason, suggest the matching visit-bundle macro(s) to pre-load for review.
    next_appt = next_visit_for(patient)
    visit_reason = next_appt&.reason.to_s.strip
    suggested = visit_reason.present? ? suggested_macros_for(visit_reason) : []

    render inertia: "EstimateShow", props: {
      # When started from the "New invoice" flow, the editor finalises as an invoice (not a quote).
      as_invoice: params[:intent].to_s == "invoice",
      estimate: {
        id: estimate.id, number: estimate.estimate_number, status: estimate.status, ai_note: estimate.ai_note,
        provider_name: estimate.provider_name,
        date: estimate.created_at.to_date.iso8601, valid_until: estimate.valid_until&.iso8601,
        medical_total: estimate.medical_total, self_total: estimate.self_total, total: estimate.total,
        visits: estimate.lines_by_visit.map { |visit, lines|
          { visit: visit, lines: lines.map { |l| line_props(l) } }
        }
      },
      practice: practice_props,
      patient: { name: patient.full_name, phone: patient.display_phone,
                 scheme: membership&.medical_scheme&.name, member_number: membership&.member_number },
      procedure_codes: ProcedureCode.where(active: true).order(:code).map { |c|
        { id: c.id, code: c.code, description: c.description,
          fee: c.default_fee_cents.present? ? c.default_fee_cents / 100.0 : nil, vat: c.vat_treatment }
      },
      # Most-used tariff codes (across all estimates) → one-click "quick add" chips so
      # reception isn't retyping the same common codes (UX research: favourites bar).
      favourite_codes: EstimateLine.where.not(procedure_code_id: nil)
        .group(:procedure_code_id).order(Arel.sql("COUNT(*) DESC")).limit(8).count.keys
        .filter_map { |id| ProcedureCode.find_by(id: id, active: true) }
        .map { |c| { id: c.id, code: c.code, description: c.description,
                     fee: c.default_fee_cents.present? ? c.default_fee_cents / 100.0 : nil, vat: c.vat_treatment } },
      # Visit-bundle macros (e.g. "New patient exam") for one-click multi-line add.
      treatment_macros: TreatmentMacro.active.order(:access_code).map { |m|
        { id: m.id, code: m.access_code, name: m.name }
      },
      # PREDICTIVE: the booked visit reason + the bundle(s) it suggests (review-flagged in the UI).
      visit_reason: visit_reason.presence,
      suggested_macros: suggested.map { |m| { id: m.id, code: m.access_code, name: m.name } },
      # Treating-dentist options (uppercased to match the invoice/statement + HPCSA lookup).
      providers: Provider.active.order(:id).map { |p| p.name.upcase },
      attachments: estimate.attachments.map { |a|
        {
          id: a.id, filename: a.filename.to_s, content_type: a.content_type,
          byte_size: a.byte_size,
          url: Rails.application.routes.url_helpers.rails_blob_path(a, only_path: true)
        }
      }
    }
  end

  def line_props(l)
    {
      id: l.id,
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

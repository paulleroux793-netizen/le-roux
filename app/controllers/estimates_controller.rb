# Estimates — read-first list (patient quotes built from a course of treatment). Additive route.
class EstimatesController < ApplicationController
  def index
    # eager-load estimate_lines — list_props reads e.estimate_lines.size (else N+1).
    estimates = Estimate.includes(:patient, :estimate_lines).order(created_at: :desc).limit(300).to_a
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

  private

  # Inertia render — extracted so the .html branch above stays a one-liner.
  def render_inertia(estimate, patient, membership)
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
                 scheme: membership&.medical_scheme&.name, member_number: membership&.member_number },
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

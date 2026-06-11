# Invoices — read-first list + compliant invoice view (the document the patient submits to their
# own medical aid). Additive route. (Ivory, Phase 3.)
class InvoicesController < ApplicationController
  def index
    # Outstanding (open/part_paid) first, biggest balance first — reception sees
    # who to chase at the top; paid/void invoices fall below by recency.
    invoices = Invoice.includes(:patient)
                      .order(Arel.sql("CASE WHEN invoices.status IN ('open','part_paid') THEN 0 ELSE 1 END, (invoices.total_cents - invoices.paid_cents) DESC, invoices.created_at DESC"))
                      .limit(300).to_a
    render inertia: "Invoices", props: {
      invoices: invoices.map { |i| list_props(i) },
      stats: {
        total: Invoice.count,
        outstanding_count: Invoice.outstanding.count,
        outstanding_amount: (Invoice.outstanding.sum("total_cents - paid_cents") / 100.0)
      }
    }
  end

  # POST /invoices/:id/write_off — clear bad debt off the books (status → written_off).
  # Admin-only once per-user auth is live.
  def write_off
    return unless require_admin!

    invoice = Invoice.find(params[:id])
    owed = invoice.balance
    reason = params[:reason].to_s.presence || "Written off"
    if invoice.write_off!(reason: reason)
      AuditService.log(action: "invoice.written_off",
        summary: "Wrote off #{invoice.invoice_number} (R#{format('%.2f', owed)}): #{reason}",
        resource: invoice, performed_by: audit_performer, ip_address: request.remote_ip)
      redirect_back fallback_location: invoice_path(invoice), notice: "Invoice written off.", status: :see_other
    else
      redirect_back fallback_location: invoice_path(invoice),
        alert: "Can't write off a void or already written-off invoice.", status: :see_other
    end
  end

  def show
    invoice = Invoice.includes(:billing_account, :payments, invoice_lines: :procedure_code,
                               patient: { scheme_memberships: :medical_scheme }).find(params[:id])
    patient = invoice.patient
    membership = patient.scheme_memberships.first

    # P9.5 — server-rendered PDF for download / WhatsApp send. Pure Ruby (Prawn).
    respond_to do |format|
      format.html { render_inertia(invoice, patient, membership) }
      format.pdf do
        AuditService.log(
          action: "invoice.pdf_downloaded",
          summary: "Downloaded invoice #{invoice.invoice_number}",
          resource: invoice,
          performed_by: audit_performer,
          ip_address: request.remote_ip
        )
        send_data DocumentPdf.invoice(invoice),
          filename: "#{invoice.invoice_number}.pdf",
          type: "application/pdf",
          disposition: "inline"
      end
    end
  end

  private

  # Inertia render — extracted so the .html branch above stays a one-liner.
  def render_inertia(invoice, patient, membership)
    render inertia: "InvoiceShow", props: {
      invoice: {
        id: invoice.id,
        number: invoice.invoice_number,
        date: invoice.invoice_date.iso8601,
        provider_name: invoice.provider_name,
        status: invoice.status,
        void: invoice.void,
        subtotal: invoice.subtotal_cents / 100.0,
        vat: invoice.vat_cents / 100.0,
        total: invoice.total,
        paid: invoice.paid_cents / 100.0,
        balance: invoice.balance,
        written_off: invoice.written_off?,
        writeable: !invoice.void? && !invoice.written_off?,
        account_id: invoice.billing_account_id,
        credit_available: (invoice.billing_account&.credit_cents.to_i || 0) / 100.0,
        medical_total: invoice.medical_total,
        self_total: invoice.self_total,
        lines: invoice.invoice_lines.map { |l|
          {
            code: l.code, description: l.description, tooth_number: l.tooth_number,
            icd10_code: l.icd10_code,
            quantity: l.quantity, unit_fee: l.unit_fee_cents / 100.0,
            vat_treatment: l.vat_treatment, medical: l.medical, self_portion: l.self_portion,
            line_total: l.line_total
          }
        },
        # R1.5 — payment timeline so the receptionist sees what's been
        # banked without leaving the page.
        payments: invoice.payments.order(received_at: :desc).map { |p|
          {
            id: p.id, method: p.method, kind: p.kind, amount: p.amount,
            reference: p.reference, notes: p.notes, reversed: p.reversed?,
            received_at: p.received_at&.iso8601
          }
        }
      },
      practice: practice_props,
      patient: {
        name: patient.full_name,
        phone: patient.phone,
        scheme: membership&.medical_scheme&.name,
        member_number: membership&.member_number
      }
    }
  end

  def practice_props
    p = PracticeBillingProfile.current
    {
      name: p.practice_name, hpcsa: p.hpcsa_number, bhf: p.bhf_practice_number.presence || "— (to be supplied)",
      company_reg: p.company_reg, vat_registered: p.vat_registered, vat_number: p.vat_number,
      practitioner: p.practitioner_name, practitioner_hpcsa: p.practitioner_hpcsa_number,
      phone: p.phone, email: p.email, address: p.address,
      bank: "#{p.bank_name} · #{p.bank_account_name} · #{p.bank_account_number} · Branch #{p.bank_branch_code}"
    }
  end

  def list_props(i)
    {
      id: i.id, number: i.invoice_number, date: i.invoice_date.iso8601,
      patient_name: i.patient.full_name, status: i.status, void: i.void,
      total: i.total, balance: i.balance
    }
  end
end

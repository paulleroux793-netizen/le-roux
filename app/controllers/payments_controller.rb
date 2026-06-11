# Payments against an invoice. R1.5 — closes the cash drawer loop.
# Card / cash / EFT, full or partial. Apply_to_invoice on the model
# does the heavy lifting — this controller is just the form handler.
class PaymentsController < ApplicationController
  # POST /invoices/:invoice_id/payments
  def create
    invoice = Invoice.find(params[:invoice_id])

    amount = params[:amount].to_f
    method = params[:method].to_s

    if amount <= 0 || amount > 20_000_000
      return redirect_back fallback_location: invoice_path(invoice),
        alert: "Amount must be between R0 and R20,000,000", status: :see_other
    end
    unless Payment::METHODS.include?(method)
      return redirect_back fallback_location: invoice_path(invoice),
        alert: "Unknown payment method: #{method}", status: :see_other
    end
    if invoice.void?
      return redirect_back fallback_location: invoice_path(invoice),
        alert: "This invoice has been voided — payments cannot be recorded against it", status: :see_other
    end

    payment = Payment.create!(
      invoice: invoice,
      patient: invoice.patient,
      billing_account: invoice.billing_account,
      method: method,
      amount_cents: (amount * 100).round,
      reference: params[:reference].presence,
      notes: params[:notes].presence
    )

    AuditService.log(
      action: "payment.recorded",
      summary: "Recorded #{method.upcase} payment of R#{format('%.2f', amount)} on invoice #{invoice.invoice_number}",
      resource: payment,
      details: { invoice_id: invoice.id, amount: amount, method: method,
                 reference: payment.reference, new_balance: invoice.reload.balance },
      performed_by: audit_performer,
      ip_address: request.remote_ip
    )

    expire_dev_page_cache("invoices")

    msg = invoice.balance <= 0 ? "Paid in full — thank you!" : "Payment recorded — R#{format('%.2f', invoice.balance)} still outstanding"
    redirect_back fallback_location: invoice_path(invoice),
      notice: msg, status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: invoice_path(invoice),
      alert: e.record.errors.full_messages.to_sentence, status: :see_other
  end

  # GET /payments/:id/receipt(.pdf) — printable receipt for a recorded payment.
  def receipt
    payment = Payment.find(params[:id])
    send_data ReceiptPdf.render(payment),
      filename: "receipt-RCT-#{payment.id}.pdf",
      type: "application/pdf", disposition: "inline"
  end

  # POST /payments/:id/reverse — undo a mis-keyed/refunded payment (puts the invoice
  # balance or account credit back; the row stays, marked reversed, for the audit trail).
  def reverse
    payment = Payment.find(params[:id])
    invoice = payment.invoice
    reason  = params[:reason].to_s.presence || "Reversed at reception"
    if payment.reverse!(reason: reason)
      AuditService.log(
        action: "payment.reversed",
        summary: "Reversed #{payment.method.upcase} payment of R#{format('%.2f', payment.amount)}#{invoice ? " on #{invoice.invoice_number}" : ''}: #{reason}",
        resource: payment,
        details: { invoice_id: invoice&.id, amount: payment.amount, reason: reason },
        performed_by: audit_performer, ip_address: request.remote_ip
      )
      expire_dev_page_cache("invoices")
      redirect_back fallback_location: (invoice ? invoice_path(invoice) : root_path),
        notice: "Payment reversed.", status: :see_other
    else
      redirect_back fallback_location: (invoice ? invoice_path(invoice) : root_path),
        alert: "This payment can't be reversed (already reversed, or not a payment/deposit).", status: :see_other
    end
  end
end

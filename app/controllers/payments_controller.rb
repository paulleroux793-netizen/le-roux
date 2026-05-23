# Payments against an invoice. R1.5 — closes the cash drawer loop.
# Card / cash / EFT, full or partial. Apply_to_invoice on the model
# does the heavy lifting — this controller is just the form handler.
class PaymentsController < ApplicationController
  # POST /invoices/:invoice_id/payments
  def create
    invoice = Invoice.find(params[:invoice_id])

    amount = params[:amount].to_f
    method = params[:method].to_s

    if amount <= 0
      return redirect_back fallback_location: invoice_path(invoice),
        alert: "Amount must be greater than zero", status: :see_other
    end
    unless Payment::METHODS.include?(method)
      return redirect_back fallback_location: invoice_path(invoice),
        alert: "Unknown payment method: #{method}", status: :see_other
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
end

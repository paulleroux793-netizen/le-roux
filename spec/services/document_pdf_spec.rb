require 'rails_helper'

# Smoke-locks the invoice/estimate PDF (DocumentPdf) — the patient-facing tax invoice with its
# medical/self claim split + "submit to your scheme" line. Completes PDF-pipeline coverage
# (alongside statement_pdf_spec). Guards the Prawn render path against regressions.
RSpec.describe DocumentPdf do
  it 'renders a valid invoice PDF' do
    patient = create(:patient)
    pc = ProcedureCode.create!(code: "T#{rand(1_000_000)}", description: 'Crown',
                               vat_treatment: 'standard', default_fee_cents: 50_000)
    invoice = Invoice.create!(patient: patient, invoice_date: Date.current, status: 'open',
                              subtotal_cents: 50_000, vat_cents: 0, total_cents: 50_000)
    invoice.invoice_lines.create!(procedure_code: pc, code: pc.code, description: pc.description,
                                  quantity: 1, unit_fee_cents: 50_000, vat_treatment: 'standard')

    pdf = described_class.invoice(invoice)
    expect(pdf[0, 5]).to eq('%PDF-')
    expect(pdf.bytesize).to be > 1_000
  end
end

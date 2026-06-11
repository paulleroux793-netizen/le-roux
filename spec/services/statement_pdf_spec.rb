require 'rails_helper'

# Smoke-locks the account StatementPdf (incl. the C23 balance-due callout + payment reference):
# it must render a valid PDF without raising. The PDF service had no spec; this guards the whole
# Prawn pipeline (title/holder boxes, transactions, balance_due_callout, aging) against regressions.
RSpec.describe StatementPdf do
  it 'renders a valid PDF for an account (with the balance-due callout)' do
    patient = create(:patient)
    account = BillingAccount.create!(billing_name: patient.full_name,
                                     account_code: "T#{rand(1_000_000)}", head_patient_id: patient.id)
    AccountPatient.create!(billing_account: account, patient: patient, relationship: 'self')

    pdf = described_class.render(account, from: 1.year.ago.to_date, to: Date.current)
    expect(pdf[0, 5]).to eq('%PDF-')
    expect(pdf.bytesize).to be > 1_000
  end
end

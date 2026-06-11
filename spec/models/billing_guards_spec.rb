require 'rails_helper'

# Locks two real money/correctness fixes that were validated live but had no CI coverage:
#  - C3: Estimate#accept_and_invoice! is idempotent — a double-submit/race can't create 2 invoices.
#  - C4: Invoice.from_course only bills items NOT already on a non-void invoice — no double-billing.
RSpec.describe 'Billing guards' do
  let(:patient) { create(:patient) }
  let(:code) do
    ProcedureCode.create!(code: "T#{rand(1_000_000)}", description: 'Crown',
                          vat_treatment: 'standard', default_fee_cents: 50_000)
  end

  describe 'Estimate#accept_and_invoice! (C3 idempotency)' do
    it 'creates exactly one invoice and blocks a second accept' do
      est = Estimate.create!(patient: patient, status: 'draft', subtotal_cents: 0, vat_cents: 0, total_cents: 0)
      est.estimate_lines.create!(procedure_code: code, code: code.code, description: code.description,
                                 quantity: 1, unit_fee_cents: 50_000, vat_treatment: 'standard')

      expect { est.accept_and_invoice! }.to change(Invoice, :count).by(1)
      expect { est.accept_and_invoice! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(Invoice.count).to eq(1) # no duplicate
    end
  end

  describe 'Invoice.from_course (C4 double-bill guard)' do
    it 'bills a completed item once and excludes it on a second generate' do
      cot = CourseOfTreatment.create!(patient: patient, setting: 'in_chair', status: 'planned')
      TreatmentItem.create!(course_of_treatment: cot, procedure_code: code, status: 'completed',
                            tooth_number: '11', fee_cents: 50_000, vat_treatment: 'standard')

      inv1 = Invoice.from_course(cot)
      inv1.save!
      expect(inv1.invoice_lines.size).to eq(1)

      inv2 = Invoice.from_course(cot)
      expect(inv2.invoice_lines.size).to eq(0) # already billed → not re-billed
    end
  end
end

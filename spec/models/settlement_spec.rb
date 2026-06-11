require 'rails_helper'

# Audit + stress test of the settlement layer: overpayment→credit, deposits, applying
# credit, payment reversal, write-off, and account-level multi-invoice allocation.
# The backbone assertion is a MONEY-CONSERVATION invariant that must hold after every op:
#   Σ active inward money (payments + deposits)  ==  Σ invoice.paid_cents (non-void)  +  account.credit_cents
RSpec.describe 'Settlement', type: :model do
  let(:patient) { create(:patient) }
  let(:account) { BillingAccount.create!(billing_name: 'Test Family', head_patient: patient) }

  def invoice(cents, date: Date.current)
    Invoice.create!(patient: patient, billing_account: account, total_cents: cents,
                    subtotal_cents: cents, vat_cents: 0, status: 'open', invoice_date: date)
  end

  # The invariant — net money received (inward minus refunds) sits either in an invoice
  # or as account credit. Holds after every operation.
  def expect_conserved
    account.reload
    inward  = account.payments.inward.sum(:amount_cents)
    refunds = account.payments.where(kind: "refund").sum(:amount_cents)
    applied = account.invoices.where(void: false).sum(:paid_cents)
    expect(inward - refunds).to eq(applied + account.credit_cents),
      "conservation broken: inward=#{inward} refunds=#{refunds} applied=#{applied} credit=#{account.credit_cents}"
  end

  describe 'overpayment → account credit' do
    it 'caps the invoice at its balance and banks the excess as credit' do
      inv = invoice(10_000)
      account.payments.create!(invoice: inv, method: 'card', amount_cents: 15_000)
      inv.reload
      expect(inv.paid_cents).to eq(10_000)
      expect(inv.status).to eq('paid')
      expect(inv.balance).to eq(0)
      expect(account.reload.credit_cents).to eq(5_000)
      expect_conserved
    end

    it 'exact and partial payments behave normally (no credit)' do
      a = invoice(10_000); account.payments.create!(invoice: a, method: 'cash', amount_cents: 10_000)
      expect(a.reload.status).to eq('paid')
      b = invoice(10_000); account.payments.create!(invoice: b, method: 'eft', amount_cents: 4_000)
      expect(b.reload.status).to eq('part_paid'); expect(b.balance).to eq(60.0)
      expect(account.reload.credit_cents).to eq(0)
      expect_conserved
    end
  end

  describe 'guards (regression)' do
    it 'never applies to a void or written-off invoice' do
      v = invoice(10_000); v.void!(reason: 'dup')
      expect(v.register_payment!(5_000)).to eq(0); expect(v.reload.paid_cents).to eq(0)
      w = invoice(10_000); w.write_off!(reason: 'bad debt')
      expect(w.register_payment!(5_000)).to eq(0); expect(w.reload.paid_cents).to eq(0)
      expect(w.written_off?).to be(true)
    end
  end

  describe 'write-off' do
    it 'clears the invoice off the books and out of outstanding' do
      inv = invoice(10_000)
      expect(Invoice.outstanding).to include(inv)
      inv.write_off!(reason: 'uncollectable')
      expect(inv.reload.status).to eq('written_off')
      expect(Invoice.outstanding).not_to include(inv)
    end
  end

  describe 'payment reversal' do
    it 'reopens the invoice and drops the payment from active' do
      inv = invoice(10_000)
      pay = account.payments.create!(invoice: inv, method: 'card', amount_cents: 10_000)
      expect(inv.reload.status).to eq('paid')
      expect(pay.reverse!(reason: 'mis-keyed')).to be(true)
      expect(inv.reload.paid_cents).to eq(0)
      expect(inv.status).to eq('open')
      expect(pay.reload.reversed?).to be(true)
      expect(account.payments.active).not_to include(pay)
      expect_conserved
    end

    it 'reverses a deposit back out of credit' do
      dep = account.payments.create!(method: 'eft', kind: 'deposit', is_deposit: true, amount_cents: 20_000, patient: patient)
      expect(account.reload.credit_cents).to eq(20_000)
      dep.reverse!(reason: 'refunded at desk')
      expect(account.reload.credit_cents).to eq(0)
      expect_conserved
    end
  end

  describe 'deposits + applying credit' do
    it 'banks a deposit as credit, then applies it to an invoice' do
      account.payments.create!(method: 'card', kind: 'deposit', is_deposit: true, amount_cents: 20_000, patient: patient)
      expect(account.reload.credit_cents).to eq(20_000)
      inv = invoice(15_000)
      applied = account.apply_credit_to(inv)
      expect(applied).to eq(15_000)
      expect(inv.reload.status).to eq('paid')
      expect(account.reload.credit_cents).to eq(5_000)
      expect(account.payments.where(kind: 'credit_applied').count).to eq(1)
      expect_conserved
    end

    it 'caps credit application at whatever credit is available' do
      account.payments.create!(method: 'card', kind: 'deposit', is_deposit: true, amount_cents: 5_000, patient: patient)
      inv = invoice(15_000)
      expect(account.apply_credit_to(inv)).to eq(5_000)
      expect(inv.reload.status).to eq('part_paid')
      expect(inv.balance).to eq(100.0)
      expect(account.reload.credit_cents).to eq(0)
      expect_conserved
    end
  end

  describe 'account-level multi-invoice allocation' do
    it 'settles invoices oldest-first and banks the remainder as credit' do
      old = invoice(10_000, date: Date.current - 10)
      new = invoice(6_000,  date: Date.current - 1)
      result = account.receive_payment(20_000, method: 'eft')
      expect(old.reload.status).to eq('paid')
      expect(new.reload.status).to eq('paid')
      expect(account.reload.credit_cents).to eq(4_000)
      expect(result[:to_credit_cents]).to eq(4_000)
      expect_conserved
    end

    it 'partially settles the last invoice when funds run short' do
      a = invoice(10_000, date: Date.current - 10)
      b = invoice(6_000,  date: Date.current - 1)
      account.receive_payment(13_000, method: 'cash')
      expect(a.reload.status).to eq('paid')
      expect(b.reload.status).to eq('part_paid')
      expect(b.balance).to eq(30.0)
      expect(account.reload.credit_cents).to eq(0)
      expect_conserved
    end
  end

  describe 'refund from credit' do
    it 'pays credit back to the patient and stays balanced' do
      account.payments.create!(method: 'card', kind: 'deposit', is_deposit: true, amount_cents: 20_000, patient: patient)
      refunded = account.refund!(8_000, method: 'cash', reason: 'overpaid')
      expect(refunded).to eq(8_000)
      expect(account.reload.credit_cents).to eq(12_000)
      expect(account.payments.where(kind: 'refund').sum(:amount_cents)).to eq(8_000)
      expect_conserved
    end

    it 'caps a refund at the available credit' do
      account.payments.create!(method: 'card', kind: 'deposit', is_deposit: true, amount_cents: 5_000, patient: patient)
      expect(account.refund!(9_999, method: 'cash')).to eq(5_000)
      expect(account.reload.credit_cents).to eq(0)
      expect_conserved
    end
  end

  describe 'statement opening/closing balance' do
    it 'carries a brought-forward opening balance into a period statement' do
      invoice(10_000, date: Date.current - 40) # prior period, unpaid
      invoice(5_000,  date: Date.current - 5)  # this period
      st = Statement.generate_for(account, period_start: Date.current - 30, period_end: Date.current)
      expect(st.opening_balance_cents).to eq(10_000)
      expect(st.closing_balance_cents).to eq(15_000)
    end
  end

  describe 'payment-record integrity' do
    it 'rejects a fully orphan payment (no invoice / account / patient)' do
      expect(Payment.new(method: 'cash', kind: 'payment', amount_cents: 5_000)).not_to be_valid
    end

    it 'accepts a payment linked to at least a patient' do
      expect(Payment.new(method: 'cash', kind: 'deposit', amount_cents: 5_000, patient: patient)).to be_valid
    end
  end

  describe 'existing payment flow is unchanged' do
    it 'a plain Payment with no kind still applies to its invoice' do
      inv = invoice(10_000)
      Payment.create!(invoice: inv, patient: patient, billing_account: account, method: 'card', amount_cents: 4_000)
      expect(inv.reload.status).to eq('part_paid')
      expect(inv.balance).to eq(60.0)
    end
  end
end

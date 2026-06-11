require 'rails_helper'

# HTTP layer for the settlement actions (write-off, payment reversal, account-level
# payment, deposit, apply-credit). Financial correctness is covered in settlement_spec;
# this proves the endpoints are wired + do the right thing.
RSpec.describe 'Settlement actions', type: :request do
  let(:patient) { create(:patient) }
  let(:account) { BillingAccount.create!(billing_name: 'Fam', head_patient: patient) }

  def invoice(cents)
    Invoice.create!(patient: patient, billing_account: account, total_cents: cents,
                    subtotal_cents: cents, vat_cents: 0, status: 'open')
  end

  it 'writes off an invoice' do
    inv = invoice(10_000)
    post write_off_invoice_path(inv), params: { reason: 'uncollectable' }
    expect(response).to have_http_status(:see_other)
    expect(inv.reload.status).to eq('written_off')
  end

  it 'reverses a payment and reopens the invoice' do
    inv = invoice(10_000)
    pay = Payment.create!(invoice: inv, billing_account: account, patient: patient, method: 'card', amount_cents: 10_000)
    expect(inv.reload.status).to eq('paid')
    post reverse_payment_path(pay), params: { reason: 'mis-keyed' }
    expect(inv.reload.status).to eq('open')
    expect(pay.reload.reversed?).to be(true)
  end

  it 'takes an account-level payment allocated oldest-first with remainder to credit' do
    a = invoice(10_000); b = invoice(6_000)
    post receive_payment_billing_account_path(account), params: { amount: '200', method: 'eft' }
    expect(a.reload.status).to eq('paid')
    expect(b.reload.status).to eq('paid')
    expect(account.reload.credit_cents).to eq(4_000)
  end

  it 'banks a deposit as credit and applies it to an invoice' do
    post deposit_billing_account_path(account), params: { amount: '200', method: 'card' }
    expect(account.reload.credit_cents).to eq(20_000)
    inv = invoice(15_000)
    post apply_credit_billing_account_path(account), params: { invoice_id: inv.id }
    expect(inv.reload.status).to eq('paid')
    expect(account.reload.credit_cents).to eq(5_000)
  end

  it 'rejects a non-positive account payment' do
    post receive_payment_billing_account_path(account), params: { amount: '0', method: 'card' }
    expect(response).to have_http_status(:see_other) # redirected with an alert, nothing recorded
    expect(account.reload.credit_cents).to eq(0)
  end

  it 'refunds account credit back to the patient' do
    post deposit_billing_account_path(account), params: { amount: '200', method: 'card' }
    expect(account.reload.credit_cents).to eq(20_000)
    post refund_billing_account_path(account), params: { amount: '50', method: 'cash', reason: 'overpaid' }
    expect(account.reload.credit_cents).to eq(15_000)
    expect(account.payments.where(kind: 'refund').sum(:amount_cents)).to eq(5_000)
  end

  describe 'write-off admin gate (per-user auth on)' do
    around do |ex|
      prev = ENV['USER_AUTH_ENABLED']; ENV['USER_AUTH_ENABLED'] = 'true'; ex.run; ENV['USER_AUTH_ENABLED'] = prev
    end
    let!(:reception) { User.create!(email: 'r@t.com', password: 'secret123', name: 'R', role: 'reception') }
    let!(:admin)     { User.create!(email: 'a@t.com', password: 'secret123', name: 'A', role: 'admin') }

    it 'blocks a non-admin from writing off' do
      post login_path, params: { email: reception.email, password: 'secret123' }
      inv = invoice(10_000)
      post write_off_invoice_path(inv), params: { reason: 'x' }
      expect(inv.reload.status).to eq('open')
    end

    it 'lets an admin write off' do
      post login_path, params: { email: admin.email, password: 'secret123' }
      inv = invoice(10_000)
      post write_off_invoice_path(inv), params: { reason: 'x' }
      expect(inv.reload.status).to eq('written_off')
    end
  end
end

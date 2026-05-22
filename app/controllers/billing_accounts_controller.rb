# Billing accounts (the unit that pays). Read-first list + show. Additive — new route.
# Populated once the patient import is unblocked (UNCERTAINTIES #13); screens built now.
class BillingAccountsController < ApplicationController
  def index
    accounts = BillingAccount.includes(:patients).order(:billing_name).limit(500).to_a
    render inertia: "BillingAccounts", props: {
      accounts: accounts.map { |a| list_props(a) },
      stats: { total: BillingAccount.count }
    }
  end

  def show
    account = BillingAccount.includes(account_patients: :patient).find(params[:id])
    render inertia: "BillingAccountShow", props: {
      account: {
        id: account.id,
        account_code: account.account_code,
        billing_name: account.billing_name,
        email: account.email,
        phone: account.phone,
        address: [ account.address_line1, account.address_line2, account.city, account.postal_code ].compact_blank.join(", "),
        members: account.account_patients.map do |ap|
          { id: ap.patient_id, name: ap.patient.full_name, phone: ap.patient.phone, relationship: ap.relationship }
        end
      }
    }
  end

  private

  def list_props(a)
    {
      id: a.id,
      account_code: a.account_code,
      billing_name: a.billing_name,
      phone: a.phone,
      member_count: a.patients.size
    }
  end
end

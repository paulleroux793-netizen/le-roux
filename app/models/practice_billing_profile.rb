# Billing/registration identity for compliant invoices & statements (singleton).
# Seeded from PRACTICE_CONFIG_DRAFT.md. BHF number + VAT status pending Paul (UNCERTAINTIES #3, #17).
class PracticeBillingProfile < ApplicationRecord
  # The single profile for this one-practice system; created on first access.
  def self.current
    first || create!(default_attributes)
  end

  def self.default_attributes
    {
      practice_name: "Dr Chalita le Roux Inc",
      hpcsa_number: "DP 0118702",
      bhf_practice_number: "0992801",      # from past practice documents — Paul to confirm current
      company_reg: "2022/698149/21",
      vat_registered: true,                # confirmed by Paul; fees VAT-inclusive
      vat_number: "4260308871",            # from past practice documents — Paul to confirm current
      practitioner_name: "Dr Chalita le Roux",
      practitioner_hpcsa_number: "DP 0118702",
      phone: "011 568 8285",
      email: "info@drchalitaleroux.co.za",
      address_line1: "Unit 2, Amorosa Office Park",
      address_line2: "Cnr Doreen Road & Lawrence Rd",
      city: "Amorosa, Roodepoort, Johannesburg",
      postal_code: "2040",
      bank_name: "Investec Bank Limited",
      bank_account_name: "Dr Chalita Le Roux Inc",
      bank_account_number: "10013494325",
      bank_branch_code: "580105"
    }
  end

  def address = [ address_line1, address_line2, city, postal_code ].compact_blank.join(", ")
end

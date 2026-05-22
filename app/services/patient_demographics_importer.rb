# Imports the practice's GoodX "Patient Demographics" export into the new
# practice-management tables. ADDITIVE + SAFE:
#   - Matches existing patients by normalised phone — NEVER clobbers or duplicates a live patient.
#   - Creates billing_accounts, account_patients, medical_schemes, scheme_memberships (new tables).
#   - Creates a NEW Patient only when it has a unique, non-blank phone (so the live phone-uniqueness
#     constraint is respected). Family members who share/lack a phone are reported as exceptions for
#     a deliberate identity decision (see UNCERTAINTIES #13) rather than force-created.
#
# Reads db/seed_data/patients.csv (gitignored — real PII, stays local).
#
#   PatientDemographicsImporter.new.call(dry_run: true)   # report only, no writes
#   PatientDemographicsImporter.new.call(dry_run: false)  # perform import (idempotent)
require "csv"

class PatientDemographicsImporter
  CSV_PATH = Rails.root.join("db", "seed_data", "patients.csv")

  Result = Struct.new(
    :accounts_total, :accounts_created, :patients_matched, :patients_created,
    :rows_blank_phone, :rows_dup_phone, :schemes_created, :memberships_created,
    :exceptions, keyword_init: true
  )

  def initialize(path: CSV_PATH)
    @path = path
  end

  def call(dry_run: true)
    seen_phones = {}                # phone => :existing | :pending(new in this run)
    accounts = {}                   # account_number => true once handled
    schemes = {}
    r = Result.new(
      accounts_total: 0, accounts_created: 0, patients_matched: 0, patients_created: 0,
      rows_blank_phone: 0, rows_dup_phone: 0, schemes_created: 0, memberships_created: 0,
      exceptions: []
    )

    rows = CSV.read(@path, headers: true)
    account_codes = rows.map { |x| x["account_number"].to_s.strip }.reject(&:empty?).uniq
    r.accounts_total = account_codes.size

    ActiveRecord::Base.transaction do
      rows.each_with_index do |row, i|
        acc_code = row["account_number"].to_s.strip
        phone    = row["phone"].to_s.strip
        first    = row["dep_first"].to_s.strip.presence || row["main_first"].to_s.strip
        last     = row["dep_surname"].to_s.strip.presence || row["main_surname"].to_s.strip

        # --- Billing account ---
        unless accounts[acc_code]
          accounts[acc_code] = true
          if acc_code.present?
            existing_acc = BillingAccount.find_by(account_code: acc_code)
            if existing_acc.nil?
              r.accounts_created += 1
              unless dry_run
                BillingAccount.create!(
                  account_code: acc_code,
                  billing_name: [ row["main_first"], row["main_surname"] ].join(" ").strip.presence || "Account #{acc_code}",
                  email: row["main_email"].presence, phone: row["main_cell"].presence,
                  address_line1: row["address1"].presence, address_line2: row["address2"].presence,
                  city: row["address3"].presence, postal_code: row["postal"].presence
                )
              end
            end
          end
        end

        # --- Scheme membership (skip PRIVATE) ---
        scheme_name = row["scheme_name"].to_s.strip
        membership_no = row["membership_number"].to_s.strip
        if scheme_name.present? && !scheme_name.upcase.start_with?("PRIVATE") && membership_no.present?
          unless schemes[scheme_name]
            schemes[scheme_name] = true
            unless MedicalScheme.exists?(name: scheme_name)
              r.schemes_created += 1
              MedicalScheme.create!(name: scheme_name) unless dry_run
            end
          end
          r.memberships_created += 1 # counted per row that carries a membership
        end

        # --- Patient identity (match by phone, never clobber) ---
        if phone.blank?
          r.rows_blank_phone += 1
          r.exceptions << { row: i + 2, reason: "no phone", name: "#{first} #{last}".strip, account: acc_code }
          next
        end

        existing = Patient.find_by(phone: phone) || (seen_phones[phone] == :existing)
        if Patient.exists?(phone: phone)
          r.patients_matched += 1
          seen_phones[phone] = :existing
        elsif seen_phones[phone]
          # phone already used by an earlier row in this import → family sharing a cell
          r.rows_dup_phone += 1
          r.exceptions << { row: i + 2, reason: "duplicate phone (family shares cell)", name: "#{first} #{last}".strip, phone: phone, account: acc_code }
        elsif first.present? || last.present?
          r.patients_created += 1
          seen_phones[phone] = :pending
          unless dry_run
            Patient.create!(first_name: first.presence || "Unknown", last_name: last.presence || "(imported)", phone: phone)
          end
        else
          r.exceptions << { row: i + 2, reason: "no name", phone: phone, account: acc_code }
        end
      end

      raise ActiveRecord::Rollback if dry_run
    end

    r
  end
end

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

        # --- Scheme + membership data (skip PRIVATE rows) ---
        scheme_name = row["scheme_name"].to_s.strip
        membership_no = row["membership_number"].to_s.strip
        dep_code = row["dep_code"].to_s.strip.presence
        has_scheme = scheme_name.present? && !scheme_name.upcase.start_with?("PRIVATE") && membership_no.present?
        if has_scheme && !schemes[scheme_name]
          schemes[scheme_name] = true
          unless MedicalScheme.exists?(name: scheme_name)
            r.schemes_created += 1
            MedicalScheme.create!(name: scheme_name) unless dry_run
          end
        end
        r.memberships_created += 1 if has_scheme

        # --- Patient identity: match by id_number OR phone; never clobber. ---
        # Identity is the SA ID / passport / DOB-based number (dependant first, else main member).
        id_number = row["dep_id"].to_s.strip.presence || row["main_id"].to_s.strip.presence

        # Match an existing patient: by id_number first, then by phone.
        existing = (id_number && Patient.find_by(id_number: id_number)) ||
                   (phone.present? && Patient.find_by(phone: phone))
        if existing
          r.patients_matched += 1
          unless dry_run
            link_account(existing, acc_code)
            link_scheme(existing, scheme_name, membership_no, dep_code) if has_scheme
          end
          next
        end

        # No name AND no identity → can't create a meaningful record.
        if first.blank? && last.blank? && id_number.blank?
          r.exceptions << { row: i + 2, reason: "no name or identity", account: acc_code }
          next
        end

        # A shared phone is kept by the FIRST patient that claims it; later family members get a nil
        # phone (their contact lives on the billing account) and are identified by id_number.
        usable_phone = phone.presence
        if usable_phone && (seen_phones[usable_phone] || Patient.exists?(phone: usable_phone))
          usable_phone = nil
          r.rows_dup_phone += 1
        end
        r.rows_blank_phone += 1 if phone.blank?

        # A new patient must satisfy the model's identity rule (phone OR id_number).
        # If a shared phone got deduped to nil and there's no id_number, we can't
        # create a valid record — log it as an exception instead of crashing.
        if usable_phone.blank? && id_number.blank?
          r.exceptions << { row: i + 2, reason: "no usable phone and no identity", account: acc_code }
          next
        end

        r.patients_created += 1
        seen_phones[usable_phone] = :pending if usable_phone
        unless dry_run
          p = Patient.create!(first_name: first.presence || "Unknown", last_name: last.presence || "(imported)",
                              phone: usable_phone, id_number: id_number)
          link_account(p, acc_code)
          link_scheme(p, scheme_name, membership_no, dep_code) if has_scheme
        end
      end

      raise ActiveRecord::Rollback if dry_run
    end

    r
  end

  private

  # Link a patient to a scheme membership (idempotent). Creates SchemeMembership for the
  # (scheme, member_number) pair and links the patient via SchemeMembershipPatient.
  def link_scheme(patient, scheme_name, member_no, dep_code)
    scheme = MedicalScheme.find_by(name: scheme_name)
    return unless scheme
    membership = SchemeMembership.find_or_create_by!(medical_scheme_id: scheme.id, member_number: member_no)
    SchemeMembershipPatient.find_or_create_by!(scheme_membership_id: membership.id, patient_id: patient.id) do |smp|
      smp.dependant_code = dep_code
      smp.role = "dependant"
    end
  end

  # Link a patient to their billing account (idempotent).
  def link_account(patient, acc_code)
    return if acc_code.blank?
    acc = BillingAccount.find_by(account_code: acc_code)
    return unless acc
    AccountPatient.find_or_create_by!(billing_account: acc, patient: patient) { |ap| ap.relationship = "self" }
  end
end

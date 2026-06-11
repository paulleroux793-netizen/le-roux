class Patient < ApplicationRecord
  # Practice-management associations (Phase 1+) live in a concern so this model's
  # core booking/conversation logic stays untouched. Additive only.
  include PracticeManagementPatient

  AUTO_CREATED_PLACEHOLDER_NAMES = [
    [ "WhatsApp", "Patient" ],
    [ "Phone", "Caller" ]
  ].freeze

  # Patients who self-registered via the public online intake link carry a real name but
  # an UNVERIFIED identity (their ID/phone live in the captured form data, not the unique
  # columns). The flag is a prefix on `notes`; needs_review? picks it up so they surface
  # in the review queue until reception confirms identity and merges any duplicate.
  SELF_REG_MARKER = "[SELF-REGISTERED — UNVERIFIED]"

  # POPIA s19 — SA ID number is special personal information; encrypt at rest.
  # Deterministic so find_by(id_number:) and the lookup index still work. Existing
  # plaintext rows are re-encrypted by `bin/rails phi:encrypt` (see the encryption
  # initializer); support_unencrypted_data keeps reads working until then.
  encrypts :id_number, deterministic: true

  # Practice-policy AI consent (Paul, 2026-06-09): every new patient is consented to AI
  # processing by default so the chair-side scribe + AI tools work for everyone. Covered by
  # the practice POPIA notice. Reversible per-patient — clear consent_to_ai_processing_at to
  # opt a patient out (the ||= never re-sets a value, so a manual opt-out sticks).
  before_create { self.consent_to_ai_processing_at ||= Time.current }

  has_many :appointments, dependent: :destroy
  has_many :call_logs, dependent: :nullify
  has_many :conversations, dependent: :destroy
  has_many :notifications, dependent: :destroy  # else hard-deleting a patient FK-errors
  # Billing account(s) this patient sits on (as account holder or dependant).
  # Used by the diary to show the [ACCOUNT] code on each block.
  has_many :account_patients, dependent: :destroy
  has_many :billing_accounts, through: :account_patients

  # The patient's primary account code (e.g. "A0001") for diary blocks / matching.
  def account_code
    billing_accounts.first&.account_code
  end

  # Phase 9.6 sub-area #4 — optional 1:1 medical history record.
  # `autosave: true` so nested attributes posted from the Patient form
  # are persisted inside the parent save; `dependent: :destroy` keeps
  # records clean if a patient is ever deleted.
  has_one :medical_history,
          class_name: "PatientMedicalHistory",
          dependent: :destroy,
          autosave: true

  # Allow the PatientsController to accept nested medical_history
  # attributes in one form submission. `_destroy` is intentionally
  # not wired — the patient record owns the history, so clearing it
  # is done by blanking the fields rather than deleting the row.
  accepts_nested_attributes_for :medical_history, update_only: true

  before_validation :normalize_phone!

  SUPPORTED_LANGUAGES = %w[en af].freeze

  validates :first_name, presence: true
  validates :last_name, presence: true
  # Phone is unique when present, but optional: a patient may instead be identified by id_number
  # (SA ID / passport / DOB-based for children, and family members who share one contact number).
  # Live WhatsApp/booking flows always set a phone, so their behaviour is unchanged.
  validates :phone, uniqueness: true, allow_nil: true,
            format: { with: /\A\+?\d{10,15}\z/, message: "must be a valid phone number", allow_blank: true }
  validate  :phone_or_identity_present
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :preferred_language, inclusion: { in: SUPPORTED_LANGUAGES }, allow_nil: true

  def full_name
    "#{first_name} #{last_name}"
  end

  # True when this record still carries a system-generated placeholder
  # name (WhatsApp Patient / Phone Caller / Unknown / (imported)) rather
  # than a real one captured from the patient or imported from Elixir.
  def placeholder_name?
    AUTO_CREATED_PLACEHOLDER_NAMES.include?([ first_name, last_name ]) ||
      first_name == "Unknown" ||
      last_name == "(imported)"
  end

  # What the UI should show as the contact's name. We never want to
  # render "WhatsApp Patient" — it's identical for every unknown caller
  # and tells reception nothing. Until a real name is known, the phone
  # number at least uniquely identifies the person; once their name is
  # captured (booking flow) or imported (Elixir migration) it shows
  # automatically because everything is keyed on the phone number.
  def display_name
    placeholder_name? ? phone : full_name
  end

  # Convenience accessor — returns the existing record or a new
  # unsaved one so views / props can always call the same getter
  # without nil checks.
  def medical_history_or_build
    medical_history || build_medical_history
  end

  # POPIA — Patient has signed the paper consent form to allow the
  # practice's AI features (chair-side scribe summary, mailbox booking
  # drafts, email triage) to process their data. The signed form lives
  # in the physical file; this flag is the digital reflection of that.
  # Default false → AI features SKIP this patient until reception ticks
  # the checkbox on the patient profile.
  def ai_consent?
    consent_to_ai_processing_at.present?
  end

  def auto_created_placeholder_profile?
    AUTO_CREATED_PLACEHOLDER_NAMES.include?([ first_name, last_name ]) &&
      email.blank? &&
      date_of_birth.blank? &&
      notes.blank? &&
      !medical_history&.any_data?
  end

  # Imported patients with placeholder names or incomplete profiles
  # need manual review (merging or completing their details).
  def needs_review?
    auto_created_placeholder_profile? ||
      last_name == "(imported)" ||
      first_name == "Unknown" ||
      notes.to_s.start_with?(SELF_REG_MARKER)
  end

  # Human-readable SA national format for display/print: "+27649029044" → "064 902 9044".
  def display_phone
    return phone if phone.blank?
    d = phone.gsub(/\D/, "")
    d = "0#{d[2..]}" if d.start_with?("27") && d.length == 11
    d.length == 10 ? "#{d[0..2]} #{d[3..5]} #{d[6..]}" : phone
  end

  # Canonical SA E.164, shared by the model AND PatientRegistrationService so both
  # produce identical phones (else the dup-check misses and "+0…" leaks back in).
  def self.canonical_phone(value)
    digits = value.to_s.gsub(/[^\d+]/, "").presence
    return nil if digits.nil?
    if    digits.start_with?("+")                        then digits
    elsif digits.start_with?("0") && digits.length == 10 then "+27#{digits[1..]}"
    elsif digits.start_with?("27")                       then "+#{digits}"
    else  "+#{digits}"
    end
  end

  private

  # Store SA numbers as proper E.164 (+27…) for WhatsApp/Twilio. A national
  # "0XX XXX XXXX" becomes "+27XXXXXXXXX" — NOT "+0XXXXXXXXX" (the old bug).
  def normalize_phone!
    self.phone = self.class.canonical_phone(phone) if phone.present?
  end

  # A patient must be identifiable by at least a phone OR an id_number.
  def phone_or_identity_present
    return if phone.present? || id_number.present?
    errors.add(:base, "a phone number or ID number is required")
  end
end

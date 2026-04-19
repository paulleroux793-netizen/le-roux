class Patient < ApplicationRecord
  AUTO_CREATED_PLACEHOLDER_NAMES = [
    [ "WhatsApp", "Patient" ],
    [ "Phone", "Caller" ]
  ].freeze

  has_many :appointments, dependent: :destroy
  has_many :call_logs, dependent: :nullify
  has_many :conversations, dependent: :destroy

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
  validates :phone, presence: true, uniqueness: true,
            format: { with: /\A\+?\d{10,15}\z/, message: "must be a valid phone number" }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :preferred_language, inclusion: { in: SUPPORTED_LANGUAGES }, allow_nil: true

  def full_name
    "#{first_name} #{last_name}"
  end

  # Convenience accessor — returns the existing record or a new
  # unsaved one so views / props can always call the same getter
  # without nil checks.
  def medical_history_or_build
    medical_history || build_medical_history
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
      first_name == "Unknown"
  end

  private

  def normalize_phone!
    normalized = phone.to_s.gsub(/\s+/, "").presence
    self.phone = normalized&.start_with?("+") ? normalized : normalized&.then { |value| "+#{value}" }
  end
end

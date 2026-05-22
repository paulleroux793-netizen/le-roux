# A document in a patient's digital file (replaces the physical files). Folders mirror the
# practice's real OneDrive structure. Binary storage backend wired later (UNCERTAINTIES #18).
class Document < ApplicationRecord
  FOLDERS = %w[
    consent_forms referral_letters befores_afters sidexis_scans
    treatment_plans correspondence personal aligners other
  ].freeze
  FOLDER_LABELS = {
    "consent_forms" => "Consent Forms", "referral_letters" => "Referral Letters",
    "befores_afters" => "Befores & Afters", "sidexis_scans" => "Sidexis Scans",
    "treatment_plans" => "Treatment Plans", "correspondence" => "Correspondence",
    "personal" => "Personal Documents", "aligners" => "Active Aligners", "other" => "Other"
  }.freeze
  SOURCES = %w[upload whatsapp_form notepad sidexis generated].freeze

  belongs_to :patient
  belongs_to :course_of_treatment, optional: true

  validates :title, presence: true
  validates :folder, inclusion: { in: FOLDERS }
  validates :source, inclusion: { in: SOURCES }
  before_validation { self.captured_at ||= Time.current }

  scope :in_folder, ->(f) { where(folder: f) }

  def folder_label = FOLDER_LABELS[folder] || folder.titleize
end

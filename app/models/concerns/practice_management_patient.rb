# Practice-management associations added to Patient WITHOUT editing the core model logic.
# Additive only: every association below points at NEW tables (Phase 1+). The live patient
# behaviour (bookings, conversations, medical history) is unchanged.
module PracticeManagementPatient
  extend ActiveSupport::Concern

  included do
    # Billing accounts this patient is linked to (via account_patients join).
    has_many :account_patients, dependent: :destroy
    has_many :billing_accounts, through: :account_patients

    # Scheme memberships (for self-claim statement details).
    has_many :scheme_membership_patients, dependent: :destroy
    has_many :scheme_memberships, through: :scheme_membership_patients

    # Phase 2 — clinical core. (class_name needed: the irregular plural doesn't auto-resolve.)
    has_many :courses_of_treatment, class_name: "CourseOfTreatment", dependent: :destroy
    has_many :clinical_notes, dependent: :destroy
    has_many :tooth_chart_entries, dependent: :destroy

    # Phase 3 — money.
    has_many :invoices, dependent: :destroy
    has_many :estimates, dependent: :destroy

    # Phase 4 — digital file.
    has_many :documents, dependent: :destroy
    has_many :form_submissions, dependent: :destroy
    has_many :notepad_pages, dependent: :destroy

    # Phase 5/6 — imaging, recalls, scribe.
    has_many :imaging_studies, dependent: :nullify
    has_many :recalls, dependent: :destroy
    has_many :scribe_sessions, dependent: :destroy
  end

  # The account that pays for this patient (first linked account, if any).
  def primary_billing_account
    billing_accounts.first
  end
end

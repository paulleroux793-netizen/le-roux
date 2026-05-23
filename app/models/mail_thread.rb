# N2 — Conversation (Gmail thread / Outlook conversation / IMAP sequence).
class MailThread < ApplicationRecord
  CLINICAL_INTENTS = %w[appointment_request insurance_inquiry treatment_question billing_issue marketing other].freeze

  belongs_to :mail_account
  belongs_to :patient, optional: true
  has_many :mail_messages, -> { order(received_at: :asc) }, dependent: :destroy

  scope :unread,    -> { where("unread_count > 0") }
  scope :inbox,     -> { where(archived: false, trashed: false) }
  scope :starred,   -> { where(starred: true) }
  scope :appointment_requests, -> { where(clinical_intent: "appointment_request") }

  # True if we matched the thread to a patient with high confidence (>=0.95).
  def confidently_matched?
    patient_id.present? && patient_match_confidence.to_f >= 0.95
  end
end

# A form sent to a patient, filled + signed on their phone via a tokenised, expiring link.
# On completion it is filed as a Document in the patient's digital file.
class FormSubmission < ApplicationRecord
  STATUSES = %w[sent opened completed expired].freeze

  belongs_to :form_template
  belongs_to :patient
  belongs_to :document, optional: true

  validates :token, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  before_validation :ensure_token, on: :create

  scope :pending, -> { where(status: %w[sent opened]) }

  def expired? = expires_at.present? && expires_at < Time.current

  # Send to the patient — tokenised link valid for 14 days. (WhatsApp delivery is wired additively
  # via an outbound job; never touches the live incoming flow.)
  def mark_sent!
    update!(status: "sent", sent_at: Time.current, expires_at: 14.days.from_now)
  end

  # Patient completed + signed on their phone → file it.
  def complete!(data:, signature_data: nil)
    transaction do
      doc = Document.create!(
        patient_id: patient_id,
        folder: form_template.key.include?("consent") ? "consent_forms" : "correspondence",
        title: "#{form_template.name} (v#{form_template.version})",
        doc_type: "form", source: "whatsapp_form",
        signed: signature_data.present?, captured_at: Time.current
      )
      update!(status: "completed", completed_at: Time.current, data: data,
              signature_data: signature_data, document: doc)
      doc
    end
  end

  private

  def ensure_token
    self.token ||= SecureRandom.urlsafe_base64(24)
  end
end

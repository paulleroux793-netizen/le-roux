# N2 — Individual email message inside a MailThread.
class MailMessage < ApplicationRecord
  # PHI at rest: patient emails carry health info (symptoms, medical-aid detail).
  # Encrypt the content columns. Safe because the mailbox search is client-side
  # (React filters already-decrypted props) — nothing queries these in SQL, and
  # the sync de-dupes on provider_message_id (not encrypted), so threading is
  # unaffected. Non-deterministic (never matched by exact value).
  encrypts :body_text
  encrypts :body_html
  encrypts :subject
  encrypts :snippet

  belongs_to :mail_thread
  belongs_to :mail_account
  has_many :mail_appointment_drafts, dependent: :destroy

  scope :unread, -> { where(read_at: nil) }
  scope :inbound, -> { where(sent_by_us: false) }

  def unread?
    read_at.nil?
  end
end

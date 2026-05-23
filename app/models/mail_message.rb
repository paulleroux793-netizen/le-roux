# N2 — Individual email message inside a MailThread.
class MailMessage < ApplicationRecord
  belongs_to :mail_thread
  belongs_to :mail_account
  has_many :mail_appointment_drafts, dependent: :destroy

  scope :unread, -> { where(read_at: nil) }
  scope :inbound, -> { where(sent_by_us: false) }

  def unread?
    read_at.nil?
  end
end

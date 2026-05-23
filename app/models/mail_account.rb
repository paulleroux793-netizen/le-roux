# N2 — Mailbox integration. Represents one connected email account
# (info@drchalitaleroux.co.za and Paul's Gmail are the initial two for
# Dr Chalita's practice).
class MailAccount < ApplicationRecord
  PROVIDERS = %w[aurinko microsoft_graph gmail_api imap].freeze
  STATUSES  = %w[connecting active error disabled].freeze

  encrypts :oauth_access_token_ciphertext
  encrypts :oauth_refresh_token_ciphertext

  has_many :mail_threads,  dependent: :destroy
  has_many :mail_messages, dependent: :destroy

  validates :provider, inclusion: { in: PROVIDERS }
  validates :address, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: "active") }
end

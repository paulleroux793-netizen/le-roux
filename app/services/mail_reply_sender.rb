require "mail"
require "base64"

# Sends a reply email via the practice's own SMTP server (real outbound mail).
# Used by reception's manual Reply, and later by approved AI draft replies.
# Reuses the mailbox login (same as IMAP) — passwords arrive base64 (env-safe).
class MailReplySender
  def self.send_reply(account:, to:, subject:, body:, in_reply_to: nil)
    cfg = smtp_config(account)
    raise "no SMTP config for #{account.address}" if cfg[:host].blank? || cfg[:pass].blank?

    msg = Mail.new
    msg.from    = account.address
    msg.to      = to
    msg.subject = subject
    msg.body    = body.to_s
    # Thread the reply in the patient's mail client (backward-compatible: nil = no header).
    if in_reply_to.present?
      msg.in_reply_to = in_reply_to
      msg.references  = in_reply_to
    end
    msg.delivery_method :smtp,
      address:              cfg[:host],
      port:                 cfg[:port],
      user_name:            cfg[:user],
      password:             cfg[:pass],
      authentication:       :login,
      enable_starttls_auto: cfg[:port] != 465,
      ssl:                  cfg[:port] == 465,
      # The cPanel/Exim host (mail.drchalitaleroux.co.za) stalls on 587 STARTTLS
      # and the gem's default read timeout is too short — give the TLS+auth
      # round-trip room. 465 (implicit SSL) is the reliable submission port here.
      open_timeout:         15,
      read_timeout:         25
    msg.deliver!
    true
  end

  def self.smtp_config(account)
    if account.address.to_s.include?("gmail")
      {
        host: ENV["CHALITA_FILING_IMAP_GMAIL_HOST"].to_s.sub("imap", "smtp").presence || "smtp.gmail.com",
        port: 587,
        user: ENV["CHALITA_FILING_IMAP_GMAIL_USER"]&.strip,
        pass: decode(ENV["CHALITA_FILING_IMAP_GMAIL_PASS_B64"])
      }
    else
      {
        host: ENV["CHALITA_MAIL_SMTP_HOST"]&.strip || ENV["CHALITA_FILING_IMAP_INFO_HOST"]&.strip,
        port: (ENV["CHALITA_MAIL_SMTP_PORT"].presence || 587).to_i,
        user: account.address,
        pass: decode(ENV["CHALITA_FILING_IMAP_INFO_PASS_B64"])
      }
    end
  end

  def self.decode(b64)
    b64.present? ? Base64.decode64(b64).strip : nil
  end
end

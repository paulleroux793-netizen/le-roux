require "net/imap"
require "mail"
require "base64"

# Reads the practice mailboxes into Ivory's unified inbox — READ-ONLY.
# We EXAMINE each folder (never SELECT) and PEEK message bodies, so the IMAP
# \Seen flags are never touched: Outlook keeps working exactly as before and
# stays the source of truth. Ivory is just an extra reader.
#
# Folder-aware: caches each account's folder list (for the Outlook-style tree)
# and syncs recent messages from every folder, tagged with their folder.
class MailboxImapSync
  ACCOUNTS = [
    { address: "info@drchalitaleroux.co.za", display_name: "Practice — info@", env: "CHALITA_FILING_IMAP_INFO" },
    { address: "chalitaleroux@gmail.com",    display_name: "Practice — Gmail", env: "CHALITA_FILING_IMAP_GMAIL" }
  ].freeze

  def self.sync_all(per_folder: 30) = new.sync_all(per_folder: per_folder)

  def sync_all(per_folder: 30)
    results = {}
    ACCOUNTS.each do |cfg|
      results[cfg[:address]] = sync_account(cfg, per_folder: per_folder)
    rescue => e
      results[cfg[:address]] = { error: "#{e.class}: #{e.message}" }
      MailAccount.find_by(address: cfg[:address])&.update(status: "error", status_message: e.message.to_s[0, 200])
    end
    results
  end

  private

  def sync_account(cfg, per_folder:)
    host = ENV["#{cfg[:env]}_HOST"]&.strip
    port = (ENV["#{cfg[:env]}_PORT"].presence || 993).to_i
    user = ENV["#{cfg[:env]}_USER"]&.strip
    pass_b64 = ENV["#{cfg[:env]}_PASS_B64"]
    pass = pass_b64.present? ? Base64.decode64(pass_b64).strip : ENV["#{cfg[:env]}_PASS"]&.strip
    raise "missing IMAP config for #{cfg[:address]}" if host.blank? || user.blank? || pass.blank?

    account = MailAccount.find_or_create_by!(address: cfg[:address]) do |a|
      a.provider = "imap"; a.display_name = cfg[:display_name]; a.status = "connecting"
    end

    imap = Net::IMAP.new(host, port: port, ssl: true)
    imap.login(user, pass)

    # Folder list for the tree (skip \Noselect containers).
    folders = imap.list("", "*").to_a.reject { |f| f.attr.include?(:Noselect) }.map(&:name)
    folders = [ "INBOX" ] if folders.empty?
    account.update!(folders: folders)

    total = 0
    folders.each do |folder|
      imap.examine(folder) # READ-ONLY
      uids = imap.uid_search([ "ALL" ]).last(per_folder)
      uids.each do |uid|
        data = imap.uid_fetch(uid, [ "FLAGS", "INTERNALDATE", "BODY.PEEK[]" ])&.first
        next unless data
        raw = data.attr["BODY[]"]
        next if raw.blank?
        upsert_message(account, folder, uid, raw, data.attr["FLAGS"] || [], data.attr["INTERNALDATE"])
        total += 1
      rescue => e
        Rails.logger.warn("[MailboxImapSync] #{folder} uid=#{uid} #{e.class}: #{e.message}")
      end
    rescue => e
      Rails.logger.warn("[MailboxImapSync] folder #{folder} skipped: #{e.class}: #{e.message}")
    end

    imap.logout rescue nil
    imap.disconnect rescue nil
    account.update!(status: "active", status_message: nil, last_synced_at: Time.current)
    { folders: folders.size, messages: total }
  end

  def upsert_message(account, folder, uid, raw, flags, internaldate)
    pmid = "#{folder}|uid-#{uid}" # IMAP UIDs are per-folder, so scope the id by folder
    return if MailMessage.exists?(mail_account_id: account.id, provider_message_id: pmid)

    m = Mail.read_from_string(raw)
    from_addr = m.from&.first.to_s
    from_name = (m[:from]&.display_names&.first rescue nil).presence || from_addr
    to_list   = Array(m.to)
    cc_list   = Array(m.cc)
    subject   = m.subject.to_s
    received  = ((m.date&.to_time rescue nil) || internaldate || Time.current)
    text      = safe_part(m, :text)
    html      = safe_part(m, :html)
    snippet   = text.to_s.gsub(/\s+/, " ").strip[0, 200]
    seen      = flags.include?(:Seen)

    thread = MailThread.find_or_create_by!(mail_account_id: account.id, provider_thread_id: pmid) do |t|
      t.subject = subject
      t.folder = folder
      t.participants = ([ from_addr ] + to_list).compact.uniq
      t.last_message_at = received
    end

    MailMessage.create!(
      mail_account: account, mail_thread: thread, provider_message_id: pmid, folder: folder,
      message_id_header: m.message_id.to_s.presence,
      from_address: from_addr.presence || "unknown", from_name: from_name,
      to_addresses: to_list, cc_addresses: cc_list, subject: subject,
      body_text: text, body_html: html, snippet: snippet,
      received_at: received, has_attachments: (m.has_attachments? rescue false),
      read_at: (seen ? received : nil), sent_by_us: false
    )
    thread.update!(
      last_message_at: received,
      message_count: thread.mail_messages.count,
      unread_count: thread.mail_messages.where(read_at: nil).count,
      subject: thread.subject.presence || subject
    )
  end

  def safe_part(mail, kind)
    if mail.multipart?
      part = kind == :text ? mail.text_part : mail.html_part
      part&.decoded
    elsif kind == :text && (mail.mime_type.nil? || mail.mime_type.to_s.start_with?("text/plain"))
      mail.body.decoded
    elsif kind == :html && mail.mime_type.to_s.start_with?("text/html")
      mail.body.decoded
    end
  rescue => _e
    nil
  end
end

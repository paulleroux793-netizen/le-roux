# N2 — Unified inbox controller. Outlook-style tri-pane: account/folder
# nav on the left, conversation list in the middle, reading pane on the
# right. This is a SCAFFOLD — actual provider sync (Aurinko, Microsoft
# Graph, Gmail API) lands in a follow-up: the model + UI are ready to
# receive data the moment the provider integration ships.
class MailController < ApplicationController
  def index
    accounts = MailAccount.order(:address).to_a

    # Threads grid: most-recent first, filterable by account, intent, unread.
    threads = MailThread.includes(:patient, :mail_account, :mail_messages)
                        .where(trashed: false, archived: false)
    threads = threads.where(mail_account_id: params[:account_id]) if params[:account_id].present?
    threads = threads.where(folder: params[:folder])              if params[:folder].present?
    threads = threads.where(clinical_intent: params[:intent])      if params[:intent].present?
    threads = threads.unread                                       if params[:filter] == "unread"
    threads = threads.starred                                      if params[:filter] == "starred"
    threads = threads.appointment_requests                         if params[:filter] == "appointment_requests"
    if params[:filter] == "drafts"
      thread_ids = MailMessage.where(id: MailAppointmentDraft.pending.select(:mail_message_id)).distinct.pluck(:mail_thread_id)
      threads = threads.where(id: thread_ids)
    end
    threads = threads.order(last_message_at: :desc).limit(200).to_a

    active_thread = (MailThread.find_by(id: params[:thread_id]) if params[:thread_id].present?)

    render inertia: "Mail/Inbox", props: {
      accounts: accounts.map { |a|
        {
          id: a.id, address: a.address, display_name: a.display_name,
          provider: a.provider, status: a.status, status_message: a.status_message,
          folders: a.folders || [],
          unread_count: MailThread.where(mail_account_id: a.id).inbox.unread.count
        }
      },
      threads: threads.map { |t| thread_list_props(t) },
      active_thread: active_thread && thread_detail_props(active_thread),
      pending_drafts_count: MailAppointmentDraft.pending.count,
      filters: {
        account_id: params[:account_id], folder: params[:folder], intent: params[:intent], filter: params[:filter]
      }
    }
  end

  # Mark a thread as read (decrement unread_count on read of its messages).
  def mark_read
    thread = MailThread.find(params[:id])
    thread.mail_messages.where(read_at: nil).update_all(read_at: Time.current)
    thread.update!(unread_count: 0)
    redirect_back fallback_location: mail_path, status: :see_other
  end

  # Reply to the sender via the practice's own SMTP (REAL outbound email).
  def reply
    thread = MailThread.find(params[:id])
    body = params[:body].to_s
    return redirect_back(fallback_location: mail_path, alert: "Reply is empty.", status: :see_other) if body.strip.empty?

    own = thread.mail_account.address.to_s
    # Reply to the last message from someone OTHER than us (the external party),
    # falling back to the last inbound, then the last message overall.
    last = thread.mail_messages.where(sent_by_us: false)
                 .reject { |m| m.from_address.to_s.casecmp?(own) }.max_by(&:received_at)
    last ||= thread.mail_messages.where(sent_by_us: false).order(:received_at).last
    last ||= thread.mail_messages.last
    to = last&.from_address
    # Refuse to send if there's no external recipient (blank, or our own address).
    if to.blank? || to.to_s.casecmp?(own)
      return redirect_back(fallback_location: mail_path, alert: "Can't reply — no external recipient on this thread.", status: :see_other)
    end

    # Idempotency guard: a fast double-click / Inertia retry must not send twice.
    # SolidCache is DB-backed/shared, so unless_exist works across processes.
    guard_key = "mail_reply:#{thread.id}:#{Digest::SHA256.hexdigest(body)}"
    unless Rails.cache.write(guard_key, 1, expires_in: 30.seconds, unless_exist: true)
      return redirect_back(fallback_location: "#{mail_path}?thread_id=#{thread.id}", notice: "Reply already sent.", status: :see_other)
    end

    subject = thread.subject.to_s
    subject = "Re: #{subject}" unless subject.match?(/\Are:/i)

    begin
      MailReplySender.send_reply(account: thread.mail_account, to: to, subject: subject, body: body,
                                 in_reply_to: last&.message_id_header)
    rescue => e
      # Release the idempotency guard so the user can retry immediately after a
      # transient SMTP failure (the send did not go through).
      Rails.cache.delete(guard_key)
      return redirect_back(fallback_location: mail_path, alert: "Send failed: #{e.message.to_s.truncate(140)}", status: :see_other)
    end

    thread.mail_messages.create!(
      mail_account: thread.mail_account, provider_message_id: "sent-#{SecureRandom.hex(8)}", folder: "Sent",
      from_address: thread.mail_account.address, to_addresses: [ to ], subject: subject,
      body_text: body, snippet: body[0, 200], received_at: Time.current, read_at: Time.current, sent_by_us: true
    )
    thread.update!(message_count: thread.mail_messages.count, last_message_at: Time.current)
    # audit_logs.summary is NOT encrypted — redact PHI: mask the recipient and drop
    # the subject (which can contain patient names / clinical detail).
    AuditService.log(action: "mail.replied", summary: "Replied to #{redact_email(to)} (reply sent)",
                     resource: thread, performed_by: audit_performer, ip_address: request.remote_ip) rescue nil
    redirect_back fallback_location: "#{mail_path}?thread_id=#{thread.id}", notice: "Reply sent to #{to}.", status: :see_other
  end

  # Remove a thread from the Ivory inbox (local only — does NOT delete from the
  # mail server / Outlook; this is "clear it from my view").
  def trash
    MailThread.find(params[:id]).update!(trashed: true)
    redirect_back fallback_location: mail_path, notice: "Removed from inbox.", status: :see_other
  end

  private

  # Mask an email for the (unencrypted) audit log: first char + ***@domain.
  # Falls back to domain-only if the local part is too short to mask.
  def redact_email(addr)
    local, domain = addr.to_s.split("@", 2)
    return "(unknown recipient)" if domain.blank?
    masked_local = local.present? ? "#{local[0]}***" : "***"
    "#{masked_local}@#{domain}"
  end

  def thread_list_props(t)
    last = t.mail_messages.last
    {
      id: t.id,
      subject: t.subject.presence || "(no subject)",
      participants: t.participants,
      message_count: t.message_count,
      unread_count: t.unread_count,
      last_message_at: t.last_message_at&.iso8601,
      starred: t.starred,
      clinical_intent: t.clinical_intent,
      mail_account_id: t.mail_account_id,
      account_address: t.mail_account.address,
      snippet: last&.snippet.to_s.truncate(120),
      from_name: last&.from_name || last&.from_address,
      patient: t.patient && { id: t.patient.id, name: t.patient.full_name, confidence: t.patient_match_confidence }
    }
  end

  def thread_detail_props(t)
    thread_list_props(t).merge(
      messages: t.mail_messages.map { |m|
        {
          id: m.id,
          from_address: m.from_address, from_name: m.from_name,
          to_addresses: m.to_addresses, cc_addresses: m.cc_addresses,
          subject: m.subject, body_text: m.body_text, body_html: m.body_html,
          received_at: m.received_at.iso8601,
          read_at: m.read_at&.iso8601,
          sent_by_us: m.sent_by_us, has_attachments: m.has_attachments,
          flagged_phi: m.flagged_phi
        }
      },
      drafts: MailAppointmentDraft.includes(:patient, :mail_message)
                                  .where(mail_message_id: t.mail_messages.pluck(:id))
                                  .map { |d|
        {
          id: d.id,
          requested_start_time: d.requested_start_time&.iso8601,
          requested_duration_minutes: d.requested_duration_minutes,
          requested_reason: d.requested_reason,
          confidence: d.confidence, status: d.status,
          draft_reply: d.extraction_metadata["draft_reply"],
          patient: d.patient && { id: d.patient.id, name: d.patient.full_name }
        }
      }
    )
  end
end

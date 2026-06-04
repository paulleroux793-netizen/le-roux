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

  private

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
          patient: d.patient && { id: d.patient.id, name: d.patient.full_name }
        }
      }
    )
  end
end

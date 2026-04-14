class ConversationsController < ApplicationController
  def index
    page_data = dev_page_cache("conversations", "index", params[:channel], params[:status], params[:source]) do
      conversations = Conversation.includes(:patient).order(updated_at: :desc)
      conversations = conversations.by_channel(params[:channel]) if params[:channel].present?
      conversations = conversations.where(status: params[:status]) if params[:status].present?
      conversations = conversations.where(source: params[:source]) if params[:source].present?

      {
        conversations: conversations.limit(100).map { |c| conversation_props(c) },
        filters: { channel: params[:channel], status: params[:status], source: params[:source] }
      }
    end

    render inertia: "Conversations", props: page_data
  end

  # POST /conversations/import
  #
  # Phase 10 — historical WhatsApp chat import. Accepts a multipart
  # file upload (.json preferred, .txt fallback) and delegates to
  # WhatsappImportService. The import is idempotent via external_id
  # so re-uploading the same file updates existing rows instead of
  # creating duplicates.
  def import
    file = params[:file]
    return redirect_to(conversations_path, alert: "Please choose a file to import.", status: :see_other) if file.blank?

    result = WhatsappImportService.import_upload(
      file,
      owner_name:    params[:owner_name].presence,
      patient_phone: params[:patient_phone].presence
    )

    notice = "Import complete — #{result.created} created, #{result.updated} updated"
    notice += ", #{result.skipped} skipped" if result.skipped.positive?
    expire_conversation_caches!
    redirect_to conversations_path, notice: notice, status: :see_other
  rescue WhatsappImportService::ImportError => e
    redirect_to conversations_path, alert: "Import failed: #{e.message}", status: :see_other
  end

  # POST /conversations/:id/reply
  #
  # Phase 10.1 — Receptionist-initiated WhatsApp reply from inside
  # the conversation detail page. Takes a plain-text `body`, sends
  # it out via WhatsappTemplateService#send_text (free-form, not a
  # template), and appends it to the JSONB messages array as an
  # "assistant" entry so the transcript stays consistent with the
  # existing webhook-driven flow.
  def reply
    conversation = Conversation.includes(:patient).find(params[:id])
    body = params[:body].to_s.strip

    if body.blank?
      return redirect_back fallback_location: conversation_path(conversation),
        alert: "Reply cannot be empty.", status: :see_other
    end

    if conversation.channel != "whatsapp"
      return redirect_back fallback_location: conversation_path(conversation),
        alert: "Replies are only supported on WhatsApp conversations.",
        status: :see_other
    end

    WhatsappTemplateService.new.send_text(conversation.patient.phone, body)
    conversation.add_message(role: "assistant", content: body, timestamp: Time.current)
    conversation.update!(status: "active") if conversation.status == "closed"
    expire_conversation_caches!

    redirect_to conversation_path(conversation),
      notice: "Reply sent to #{conversation.patient.full_name}.",
      status: :see_other
  rescue WhatsappTemplateService::Error => e
    redirect_back fallback_location: conversation_path(params[:id]),
      alert: "Send failed: #{e.message}", status: :see_other
  end

  def show
    page_data = dev_page_cache("conversations", "show", params[:id]) do
      conversation = Conversation.includes(:patient).find(params[:id])

      {
        conversation: detailed_conversation_props(conversation)
      }
    end

    render inertia: "ConversationShow", props: page_data
  end

  private

  def conversation_props(conversation)
    patient = conversation.patient
    display_name = patient.full_name.presence || patient.phone
    {
      id: conversation.id,
      patient_name: display_name,
      patient_phone: patient.phone,
      channel: conversation.channel,
      status: conversation.status,
      source: conversation.source,
      topic: conversation.topic,
      message_count: conversation.messages&.length || 0,
      last_message: conversation.messages&.last&.dig("content")&.truncate(80),
      started_at: conversation.started_at&.iso8601,
      updated_at: conversation.updated_at.iso8601,
      imported_at: conversation.imported_at&.iso8601,
      whatsapp_url: whatsapp_url_for(patient.phone)
    }
  end

  # wa.me links require digits only — strip the leading "+" and any
  # formatting so "tel:+27 83 123 4567" still produces a working URL.
  def whatsapp_url_for(phone)
    return nil if phone.blank?
    digits = phone.to_s.gsub(/\D/, "")
    "https://wa.me/#{digits}"
  end

  def detailed_conversation_props(conversation)
    patient = conversation.patient
    {
      id: conversation.id,
      patient_name: patient.full_name.presence || patient.phone,
      patient_phone: patient.phone,
      patient_id: conversation.patient_id,
      channel: conversation.channel,
      status: conversation.status,
      source: conversation.source,
      topic: conversation.topic,
      messages: conversation.messages || [],
      started_at: conversation.started_at&.iso8601,
      ended_at: conversation.ended_at&.iso8601
    }
  end

  def expire_conversation_caches!
    expire_dev_page_cache("conversations/index")
    expire_dev_page_cache("conversations/show")
    expire_dev_page_cache("dashboard")
  end
end

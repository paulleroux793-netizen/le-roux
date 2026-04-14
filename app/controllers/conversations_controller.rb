class ConversationsController < ApplicationController
  def index
    conversations = Conversation.includes(:patient).order(updated_at: :desc)
    conversations = conversations.by_channel(params[:channel]) if params[:channel].present?
    conversations = conversations.where(status: params[:status]) if params[:status].present?
    conversations = conversations.where(source: params[:source]) if params[:source].present?

    render inertia: "Conversations", props: {
      conversations: conversations.limit(100).map { |c| conversation_props(c) },
      filters: { channel: params[:channel], status: params[:status], source: params[:source] }
    }
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
    redirect_to conversations_path, notice: notice, status: :see_other
  rescue WhatsappImportService::ImportError => e
    redirect_to conversations_path, alert: "Import failed: #{e.message}", status: :see_other
  end

  def show
    conversation = Conversation.includes(:patient).find(params[:id])

    render inertia: "ConversationShow", props: {
      conversation: detailed_conversation_props(conversation)
    }
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
    {
      id: conversation.id,
      patient_name: conversation.patient.full_name,
      patient_phone: conversation.patient.phone,
      patient_id: conversation.patient_id,
      channel: conversation.channel,
      status: conversation.status,
      messages: conversation.messages || [],
      started_at: conversation.started_at&.iso8601,
      ended_at: conversation.ended_at&.iso8601
    }
  end
end

class ConversationsController < ApplicationController
  def index
    page_data = dev_page_cache("conversations", "index", params[:channel], params[:status], params[:source], params[:tag]) do
      conversations = Conversation.includes(:patient).order(updated_at: :desc)
      conversations = conversations.by_channel(params[:channel]) if params[:channel].present?
      conversations = conversations.where(status: params[:status]) if params[:status].present?
      conversations = conversations.where(source: params[:source]) if params[:source].present?
      conversations = conversations.tagged(params[:tag]) if params[:tag].present?

      # Collect all unique tags across conversations for autocomplete
      all_tags = Conversation.where.not(tags: []).pluck(:tags).flatten.uniq.sort

      {
        conversations: conversations.limit(100).map { |c| conversation_props(c) },
        all_tags: all_tags,
        filters: { channel: params[:channel], status: params[:status], source: params[:source], tag: params[:tag] }
      }
    end

    render inertia: "Conversations", props: page_data
  end

  # POST /conversations/import
  #
  # Accepts a multipart file upload (.json, .txt, or .zip) and ingests
  # historical WhatsApp conversations. Files under 1 MB are processed
  # inline and redirect immediately with results. Files ≥ 1 MB are
  # saved to tmp/imports/ and queued as a BulkWhatsappImportJob; a
  # dashboard notification appears when the job completes.
  INLINE_IMPORT_THRESHOLD = 1.megabyte

  def import
    file = params[:file]
    return redirect_to(conversations_path, alert: "Please choose a file to import.", status: :see_other) if file.blank?

    owner_name    = params[:owner_name].presence
    patient_phone = params[:patient_phone].presence

    if file.size >= INLINE_IMPORT_THRESHOLD
      enqueue_background_import(file, owner_name: owner_name, patient_phone: patient_phone)
    else
      inline_import(file, owner_name: owner_name, patient_phone: patient_phone)
    end
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

  # PATCH /conversations/:id/update_tags
  #
  # Phase 10.3 — update conversation tags for AI improvement workflow.
  # Accepts { tags: ["tag1", "tag2"] } and replaces the tags array.
  def update_tags
    conversation = Conversation.find(params[:id])
    tags = Array(params[:tags]).map(&:strip).reject(&:blank?).uniq
    conversation.update!(tags: tags)
    expire_conversation_caches!

    redirect_back fallback_location: conversation_path(conversation),
      notice: "Tags updated", status: :see_other
  end

  # GET /conversations/export_tagged
  #
  # Phase 10.3 — export tagged conversations as JSON for prompt engineering.
  # Filter by tag via ?tag=good-booking-flow parameter.
  def export_tagged
    conversations = Conversation.includes(:patient).order(updated_at: :desc)
    conversations = conversations.tagged(params[:tag]) if params[:tag].present?
    conversations = conversations.limit(500)

    export = conversations.map do |c|
      {
        id: c.id,
        patient_phone: c.patient.phone,
        patient_name: c.patient.full_name,
        channel: c.channel,
        source: c.source,
        topic: c.topic,
        language: c.language,
        tags: c.tags,
        messages: c.messages,
        started_at: c.started_at&.iso8601,
        ended_at: c.ended_at&.iso8601
      }
    end

    send_data export.to_json,
      filename: "conversations-#{params[:tag] || 'all'}-#{Date.current.iso8601}.json",
      type: "application/json"
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
      language: conversation.language,
      tags: conversation.tags || [],
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
      language: conversation.language,
      tags: conversation.tags || [],
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

  def inline_import(file, owner_name:, patient_phone:)
    result = WhatsappImportService.import_upload(
      file,
      owner_name:    owner_name,
      patient_phone: patient_phone
    )

    notice = "Import complete — #{result.created} created, #{result.updated} updated"
    notice += ", #{result.skipped} skipped" if result.skipped.positive?
    notice += " (#{result.errors.size} error(s) — check logs)" if result.errors.any?
    expire_conversation_caches!
    redirect_to conversations_path, notice: notice, status: :see_other
  end

  def enqueue_background_import(file, owner_name:, patient_phone:)
    # Persist the upload to a temp path so the job can read it after the
    # request completes (uploaded_file IO is closed by Rack after the response).
    tmp_dir  = Rails.root.join("tmp", "imports")
    FileUtils.mkdir_p(tmp_dir)
    filename = "#{SecureRandom.hex(8)}_#{File.basename(file.original_filename)}"
    tmp_path = tmp_dir.join(filename).to_s

    File.binwrite(tmp_path, file.read)

    BulkWhatsappImportJob.perform_later(
      file_path:         tmp_path,
      original_filename: file.original_filename,
      owner_name:        owner_name,
      patient_phone:     patient_phone
    )

    redirect_to conversations_path,
      notice: "Import queued — your file is being processed in the background. You'll see a notification when it's done.",
      status: :see_other
  end
end

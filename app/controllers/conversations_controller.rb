class ConversationsController < ApplicationController
  def index
    # WhatsApp-Web-style 2-column layout: sidebar list + selected thread on the
    # right. The optional ?selected_id= param hydrates the full thread alongside
    # the list so the SPA doesn't need a second round-trip when you click a row.
    selected_id = params[:selected_id].presence
    channel     = params[:channel].presence
    page_data = dev_page_cache("conversations", "index", channel, params[:status], params[:source], params[:tag], selected_id) do
      rows = []

      # WhatsApp / voice conversations (skipped when the filter is set to web chat).
      unless channel == "web_chat"
        convos = Conversation.includes(:patient).order(updated_at: :desc)
        convos = convos.by_channel(channel) if channel.present?
        convos = convos.where(status: params[:status]) if params[:status].present?
        convos = convos.where(source: params[:source]) if params[:source].present?
        convos = convos.tagged(params[:tag]) if params[:tag].present?
        rows.concat(convos.limit(100).map { |c| conversation_props(c) })
      end

      # Website chat-widget sessions, shown as the "web_chat" channel in the SAME list. They carry
      # no tags and are always live, so they're excluded when those filters are active.
      show_web = (channel.nil? || channel == "web_chat") && params[:tag].blank? &&
                 (params[:source].blank? || params[:source] == "live")
      if show_web
        webs = WebChatSession.includes(:patient).order(Arel.sql("COALESCE(last_seen_at, updated_at) DESC"))
        webs = webs.where(status: params[:status]) if params[:status].present?
        rows.concat(webs.limit(100).map { |s| web_session_props(s) })
      end

      conversations = rows.sort_by { |h| h[:updated_at].to_s }.reverse.first(100)
      all_tags = Conversation.where.not(tags: []).pluck(:tags).flatten.uniq.sort

      {
        conversations: conversations,
        selected_conversation: load_selected(selected_id),
        all_tags: all_tags,
        filters: { channel: channel, status: params[:status], source: params[:source], tag: params[:tag] }
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

    # Reception takeover: pause AI for the configured window (default 4 hours)
    # so it does not contradict the human reply on the next inbound message.
    # See CODE_LOCKED_GUARDRAILS §8.2 and PracticeConfig.ai_pause_hours.
    conversation.pause_ai!

    AuditService.log(
      action: "conversation.replied",
      summary: "Sent manual reply to #{conversation.patient.full_name} via WhatsApp (AI paused #{PracticeConfig.ai_pause_hours}h)",
      resource: conversation,
      details: {
        patient_phone: conversation.patient.phone,
        body: body.truncate(120),
        ai_paused_until: conversation.ai_paused_until.iso8601
      },
      performed_by: audit_performer,
      ip_address: request.remote_ip
    )
    expire_conversation_caches!

    redirect_to conversation_path(conversation),
      notice: "Reply sent to #{conversation.patient.full_name}. AI paused for #{PracticeConfig.ai_pause_hours} hours.",
      status: :see_other
  rescue WhatsappTemplateService::Error => e
    redirect_back fallback_location: conversation_path(params[:id]),
      alert: "Send failed: #{e.message}", status: :see_other
  end

  # POST /conversations/:id/forward — forward a message from this chat to ANOTHER WhatsApp
  # conversation (like WhatsApp's forward). Params: message (text to forward), to_conversation_id.
  def forward
    source = Conversation.find(params[:id])
    body   = params[:message].to_s.strip
    target = Conversation.includes(:patient).find_by(id: params[:to_conversation_id])

    return redirect_back(fallback_location: conversation_path(source), alert: "Nothing to forward.", status: :see_other) if body.blank?
    return redirect_back(fallback_location: conversation_path(source), alert: "Pick a conversation to forward to.", status: :see_other) if target.nil?
    if target.channel != "whatsapp" || target.patient&.phone.blank?
      return redirect_back(fallback_location: conversation_path(source), alert: "Can only forward to a WhatsApp conversation that has a phone number.", status: :see_other)
    end

    WhatsappTemplateService.new.send_text(target.patient.phone, body)
    target.add_message(role: "assistant", content: body, timestamp: Time.current)
    target.update!(status: "active") if target.status == "closed"
    target.pause_ai!

    AuditService.log(
      action: "conversation.forwarded",
      summary: "Forwarded a message to #{target.patient&.full_name} via WhatsApp (from #{source.patient&.full_name})",
      resource: target,
      details: { from_conversation_id: source.id, body: body.truncate(120) },
      performed_by: audit_performer,
      ip_address: request.remote_ip
    )
    expire_conversation_caches!

    redirect_to conversation_path(target),
      notice: "Message forwarded to #{target.patient&.full_name}. AI paused for #{PracticeConfig.ai_pause_hours} hours.",
      status: :see_other
  rescue WhatsappTemplateService::Error => e
    redirect_back fallback_location: conversation_path(params[:id]),
      alert: "Forward failed (patient may be outside the 24-hour window): #{e.message}", status: :see_other
  end

  # PATCH /conversations/:id/resume_ai
  #
  # Reception clears the AI standby pause on a conversation, e.g. when the
  # human-to-human exchange is concluded and the AI can take over again.
  def resume_ai
    conversation = Conversation.find(params[:id])
    conversation.resume_ai!
    AuditService.log(
      action: "conversation.ai_resumed",
      summary: "Re-enabled AI on #{conversation.patient.full_name}'s conversation",
      resource: conversation,
      performed_by: audit_performer,
      ip_address: request.remote_ip
    )
    expire_conversation_caches!

    redirect_back fallback_location: conversation_path(conversation),
      notice: "AI re-enabled on this conversation.",
      status: :see_other
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
      detail = load_selected(params[:id])
      raise ActiveRecord::RecordNotFound unless detail

      { conversation: detail }
    end

    render inertia: "ConversationShow", props: page_data
  end

  private

  # Hydrate the selected thread for the right-hand pane / show page. A "w-"-prefixed id is a
  # web-chat session; everything else is a WhatsApp/voice Conversation. Returns detailed props or nil.
  def load_selected(selected_id)
    return nil if selected_id.blank?

    if selected_id.to_s.start_with?("w-")
      s = WebChatSession.includes(:patient).find_by(id: selected_id.to_s.delete_prefix("w-"))
      s && detailed_web_session_props(s)
    else
      c = Conversation.includes(:patient).find_by(id: selected_id)
      c && detailed_conversation_props(c)
    end
  end

  def conversation_props(conversation)
    patient = conversation.patient
    {
      id: conversation.id,
      patient_name: patient.display_name,
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
      patient_name: patient.display_name,
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

  # ── Web-chat sessions rendered in the SAME Conversations UI ────────────────
  # Same prop shape as a Conversation so the existing list + thread view render them unchanged.
  # The id is prefixed "w-" so clicks route to the WebChatSession. Reply/forward stay WhatsApp-only
  # (the frontend already gates on channel === "whatsapp"), so web chats show read-only.
  def web_session_name(s)
    s.patient&.display_name.presence || s.visitor_name.presence || "Web visitor"
  end

  def web_session_props(s)
    {
      id: "w-#{s.id}",
      patient_name: web_session_name(s),
      patient_phone: s.visitor_phone,
      channel: "web_chat",
      status: s.status,
      source: "live",
      topic: nil,
      language: s.language,
      tags: [],
      message_count: s.messages&.length || 0,
      last_message: s.messages&.last&.dig("content")&.to_s&.truncate(80),
      started_at: s.created_at&.iso8601,
      updated_at: (s.last_seen_at || s.updated_at).iso8601,
      imported_at: nil,
      whatsapp_url: (s.visitor_phone.present? ? whatsapp_url_for(s.visitor_phone) : nil)
    }
  end

  def detailed_web_session_props(s)
    {
      id: "w-#{s.id}",
      patient_name: web_session_name(s),
      patient_phone: s.visitor_phone,
      patient_id: s.patient_id,
      channel: "web_chat",
      status: s.status,
      source: "live",
      topic: nil,
      language: s.language,
      tags: [],
      messages: s.messages || [],
      started_at: s.created_at&.iso8601,
      ended_at: nil
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

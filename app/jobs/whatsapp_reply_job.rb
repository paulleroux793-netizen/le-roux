class WhatsappReplyJob < ApplicationJob
  queue_as :default

  def perform(from:, message:, twilio_params: {})
    # Per-patient serialization (research-backed, 2026-06-04): two messages from
    # the SAME WhatsApp number (a Twilio at-least-once retry, or the patient
    # double-sending) can otherwise be processed CONCURRENTLY by the worker's
    # thread pool and race — both passing the slot check, both attempting a
    # booking, producing a duplicate/false confirmation. A Postgres advisory lock
    # keyed on the phone number forces one-at-a-time processing per patient. The
    # lock auto-releases in `ensure`; it's session-scoped to this thread's
    # connection, so lock + work + unlock all run on the same connection.
    with_patient_lock(from) do
      media_attachments = WhatsappService.extract_media_attachments(twilio_params)

      result = WhatsappService.new.handle_incoming(
        from: from,
        message: message,
        twilio_params: twilio_params,
        media_attachments: media_attachments
      )

      # handle_incoming returns nil when the conversation is in reception-takeover
      # standby (AI paused for X hours after a human reply). In that case we
      # intentionally send no reply — reception is dealing with this conversation.
      #
      # Reply uses the same sender the patient messaged (sandbox stays on sandbox,
      # production replies from production). This lets stress tests on sandbox
      # not bill credits against the production WABA.
      inbound_to = twilio_params["To"] || twilio_params[:To]
      send_reply(from, result&.dig(:response), from_number: inbound_to)
    end
  rescue StandardError => e
    Rails.logger.error("[WhatsappReplyJob] Error processing message from #{from}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    send_reply(from, "I'm sorry, something went wrong on our end. Please try again or call us directly.")
  end

  private

  # Serialize all processing for one phone number via a Postgres session-level
  # advisory lock. Key is a stable 63-bit hash of the number. Blocks (waits) if
  # another job holds the lock for the same patient, so messages are handled in
  # order rather than racing.
  def with_patient_lock(phone)
    key = Digest::SHA256.hexdigest("wa-patient:#{phone}")[0, 15].to_i(16) # < 2^60, fits bigint
    conn = ActiveRecord::Base.connection
    conn.execute("SELECT pg_advisory_lock(#{key})")
    begin
      yield
    ensure
      conn.execute("SELECT pg_advisory_unlock(#{key})")
    end
  end

  def send_reply(to_phone, message, from_number: nil)
    return if message.blank?

    # Outbound compliance gate — the SINGLE choke point through which every
    # patient-facing WhatsApp reply passes (normal AI replies, fallbacks, and
    # the error-path message above all route here). Scrub the text for banned
    # phrasing (after-hours/24-hr/weekend promises, direct medical-aid billing
    # claims, medication dosing, superlatives, Pretoria geo) BEFORE it leaves
    # the building. Logging happens inside ComplianceFilter.scrub; we add a
    # job-level breadcrumb so flagged sends are greppable alongside the send.
    scrubbed = ComplianceFilter.scrub(message)
    if scrubbed[:flagged].any?
      Rails.logger.warn(
        "[WhatsappReplyJob] Compliance filter rewrote reply to #{to_phone} " \
        "before send. rules=#{scrubbed[:flagged].inspect}"
      )
    end

    WhatsappTemplateService.new(from_number: from_number).send_text(to_phone, scrubbed[:text])
  rescue StandardError => e
    Rails.logger.error("[WhatsappReplyJob] Failed to send reply to #{to_phone}: #{e.message}")
  end
end

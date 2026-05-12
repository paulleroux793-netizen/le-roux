class WhatsappReplyJob < ApplicationJob
  queue_as :default

  def perform(from:, message:, twilio_params: {})
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
  rescue StandardError => e
    Rails.logger.error("[WhatsappReplyJob] Error processing message from #{from}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    send_reply(from, "I'm sorry, something went wrong on our end. Please try again or call us directly.")
  end

  private

  def send_reply(to_phone, message, from_number: nil)
    return if message.blank?

    WhatsappTemplateService.new(from_number: from_number).send_text(to_phone, message)
  rescue StandardError => e
    Rails.logger.error("[WhatsappReplyJob] Failed to send reply to #{to_phone}: #{e.message}")
  end
end

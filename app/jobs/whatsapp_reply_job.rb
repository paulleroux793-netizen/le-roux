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
    send_reply(from, result&.dig(:response))
  rescue StandardError => e
    Rails.logger.error("[WhatsappReplyJob] Error processing message from #{from}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    send_reply(from, "I'm sorry, something went wrong on our end. Please try again or call us directly.")
  end

  private

  def send_reply(to_phone, message)
    return if message.blank?

    WhatsappTemplateService.new.send_text(to_phone, message)
  rescue StandardError => e
    Rails.logger.error("[WhatsappReplyJob] Failed to send reply to #{to_phone}: #{e.message}")
  end
end

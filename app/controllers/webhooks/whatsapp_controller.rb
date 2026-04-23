module Webhooks
  class WhatsappController < ActionController::API
    before_action :validate_twilio_signature

    # POST /webhooks/whatsapp
    # Receives incoming WhatsApp messages from Twilio.
    #
    # We respond with an empty TwiML immediately so Twilio doesn't
    # time out (the AI + remote DB can take 10+ seconds). The actual
    # reply is sent asynchronously via WhatsAppReplyJob which calls
    # the Twilio Messages API directly.
    def incoming
      sender = params["From"]&.gsub("whatsapp:", "")
      body = params["Body"]&.strip
      button_payload = params["ButtonPayload"] || params["ButtonText"]

      if sender.blank? || (body.blank? && button_payload.blank?)
        head :bad_request
        return
      end

      message = button_payload.presence || body

      # Admin commands from Paul Le Roux are handled synchronously and bypass the AI.
      if AdminWhatsappService.admin?(sender)
        AdminWhatsappService.new(sender).handle(message)
        respond_with_empty_twiml
        return
      end

      # Enqueue async processing — reply comes via Twilio REST API
      WhatsappReplyJob.perform_later(
        from: sender,
        message: message,
        twilio_params: params.permit(
          :MessageSid, :SmsSid, :SmsMessageSid, :AccountSid, :MessagingServiceSid,
          :From, :To, :Body, :NumMedia, :NumSegments,
          :ButtonPayload, :ButtonText, :WaId, :ProfileName,
          :ReferralNumMedia, :Forwarded, :FreqCapFiltered
        ).to_h
      )

      # Return empty TwiML immediately so Twilio doesn't retry
      respond_with_empty_twiml
    rescue StandardError => e
      Rails.logger.error("[WhatsApp Webhook] Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      respond_with_empty_twiml
    end

    private

    def validate_twilio_signature
      return if Rails.env.test? || Rails.env.development?

      validator = Twilio::Security::RequestValidator.new(ENV.fetch("TWILIO_AUTH_TOKEN"))
      # Use APP_BASE_URL so the URL matches what Twilio signed regardless of
      # how the reverse proxy reconstructs the scheme/host.
      base = ENV.fetch("APP_BASE_URL", request.base_url).delete_suffix("/")
      url  = "#{base}#{request.path}"
      url += "?#{request.query_string}" if request.query_string.present?
      twilio_signature = request.headers["X-Twilio-Signature"]

      unless validator.validate(url, request.POST, twilio_signature.to_s)
        Rails.logger.warn("[WhatsApp Webhook] Invalid Twilio signature from #{request.remote_ip}")
        head :forbidden
      end
    end

    def respond_with_empty_twiml
      twiml = Twilio::TwiML::MessagingResponse.new
      render xml: twiml.to_xml, content_type: "text/xml"
    end
  end
end

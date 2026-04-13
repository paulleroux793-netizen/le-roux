module Webhooks
  class WhatsappController < ActionController::API
    before_action :validate_twilio_signature

    # POST /webhooks/whatsapp
    # Receives incoming WhatsApp messages from Twilio
    def incoming
      sender = params["From"]&.gsub("whatsapp:", "")
      body = params["Body"]&.strip
      button_payload = params["ButtonPayload"] || params["ButtonText"]

      if sender.blank? || (body.blank? && button_payload.blank?)
        head :bad_request
        return
      end

      # Use button payload as the message if it's a quick reply tap
      message = button_payload.presence || body

      result = WhatsappService.new.handle_incoming(
        from: sender,
        message: message,
        twilio_params: params.permit!.to_h
      )

      respond_with_twiml(result[:response])
    rescue StandardError => e
      Rails.logger.error("[WhatsApp Webhook] Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      respond_with_twiml("I'm sorry, something went wrong on our end. Please try again or call us directly.")
    end

    private

    def validate_twilio_signature
      return if Rails.env.test? || Rails.env.development?

      validator = Twilio::Security::RequestValidator.new(ENV.fetch("TWILIO_AUTH_TOKEN"))
      url = request.original_url
      twilio_signature = request.headers["X-Twilio-Signature"]

      unless validator.validate(url, request.POST, twilio_signature.to_s)
        Rails.logger.warn("[WhatsApp Webhook] Invalid Twilio signature from #{request.remote_ip}")
        head :forbidden
      end
    end

    def respond_with_twiml(message)
      twiml = Twilio::TwiML::MessagingResponse.new do |r|
        r.message(body: message)
      end

      render xml: twiml.to_xml, content_type: "text/xml"
    end
  end
end

module Webhooks
  class VoiceController < ActionController::API
    before_action :validate_twilio_signature

    # POST /webhooks/voice
    # Twilio calls this when a patient first dials in.
    def incoming
      call_sid = params["CallSid"]
      caller    = params["From"]

      twiml = VoiceService.new.handle_incoming(call_sid: call_sid, caller: caller)
      render xml: twiml, content_type: "text/xml"
    rescue StandardError => e
      Rails.logger.error("[Voice] Error in incoming: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
      render xml: error_twiml("We're having a technical issue. Please call back or send us a WhatsApp message."),
             content_type: "text/xml"
    end

    # POST /webhooks/voice/gather
    # Twilio calls this after each speech input from the patient.
    def gather
      call_sid      = params["CallSid"]
      speech_result = params["SpeechResult"]
      confidence    = params["Confidence"].to_f

      twiml = VoiceService.new.handle_gather(
        call_sid: call_sid,
        speech_result: speech_result,
        confidence: confidence
      )
      render xml: twiml, content_type: "text/xml"
    rescue StandardError => e
      Rails.logger.error("[Voice] Error in gather: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
      render xml: error_twiml("I'm sorry, something went wrong. Please try speaking again or send us a WhatsApp message."),
             content_type: "text/xml"
    end

    # POST /webhooks/voice/status
    # Twilio calls this as the call lifecycle changes (completed, busy, no-answer, etc.).
    def status
      VoiceService.new.handle_status(
        call_sid:    params["CallSid"],
        call_status: params["CallStatus"],
        duration:    params["CallDuration"]&.to_i
      )
      head :ok
    rescue StandardError => e
      Rails.logger.error("[Voice] Error in status callback: #{e.message}")
      head :ok
    end

    # POST /webhooks/voice/confirmation
    # Twilio calls this when an outbound confirmation call (placed by ConfirmationService) is answered.
    # The appointment_id is passed as a query parameter in the URL.
    def confirmation
      appointment = Appointment.find_by(id: params[:appointment_id])
      twiml = VoiceService.new.confirmation_twiml(appointment)
      render xml: twiml, content_type: "text/xml"
    rescue StandardError => e
      Rails.logger.error("[Voice] Error in confirmation TwiML: #{e.message}")
      render xml: error_twiml("Thank you for answering. Please call us back at your convenience."),
             content_type: "text/xml"
    end

    # POST /webhooks/voice/confirmation_gather
    # Handles the patient's DTMF keypress response to the outbound confirmation call.
    # 1 = confirm, 2 = reschedule, 3 = cancel
    def confirmation_gather
      twiml = VoiceService.new.handle_confirmation_gather(
        call_sid:       params["CallSid"],
        digits:         params["Digits"],
        appointment_id: params[:appointment_id]
      )
      render xml: twiml, content_type: "text/xml"
    rescue StandardError => e
      Rails.logger.error("[Voice] Error in confirmation_gather: #{e.message}")
      render xml: error_twiml("Thank you. If you need help, please call us or send a WhatsApp message."),
             content_type: "text/xml"
    end

    private

    def validate_twilio_signature
      return if Rails.env.test? || Rails.env.development?

      validator       = Twilio::Security::RequestValidator.new(ENV.fetch("TWILIO_AUTH_TOKEN"))
      url             = request.original_url
      twilio_signature = request.headers["X-Twilio-Signature"]

      unless validator.validate(url, request.POST, twilio_signature.to_s)
        Rails.logger.warn("[Voice] Invalid Twilio signature from #{request.remote_ip}")
        head :forbidden
      end
    end

    def error_twiml(message)
      Twilio::TwiML::VoiceResponse.new do |r|
        r.say(message: message, voice: VoiceService::VOICE)
        r.hangup
      end.to_xml
    end
  end
end

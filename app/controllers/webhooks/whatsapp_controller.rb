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
      # Idempotency guard: Twilio retries webhooks if it doesn't get a fast 200.
      # Re-processing the same message duplicates Anthropic calls + bloats conversation
      # history. Primary dedupe is a DB-UNIQUE record on MessageSid (bulletproof,
      # survives restarts/cache eviction — Twilio is at-least-once and reuses the
      # SID on retry). The 2-minute cache is kept as a fast first-line check.
      sid = params["MessageSid"].to_s.presence
      if sid && !Rails.cache.write("twilio_webhook:#{sid}", Time.current.to_i, expires_in: 2.minutes, unless_exist: true)
        Rails.logger.info("[WhatsApp Webhook] Duplicate webhook (cache) #{sid}, skipping")
        respond_with_empty_twiml
        return
      end
      if sid && !WebhookReceipt.first_seen?(sid, type: "whatsapp_inbound")
        Rails.logger.info("[WhatsApp Webhook] Duplicate webhook (db) #{sid}, skipping")
        respond_with_empty_twiml
        return
      end

      sender = params["From"]&.gsub("whatsapp:", "")
      body = params["Body"]&.strip
      button_payload = params["ButtonPayload"] || params["ButtonText"]

      if sender.blank? || (body.blank? && button_payload.blank?)
        head :bad_request
        return
      end

      # Per-sender abuse rate limit. This number is PUBLIC (Google Ads + website),
      # so a single sender flooding it would otherwise rack up Anthropic + Twilio
      # cost and could drown out real patients. A genuine booking conversation is
      # well under this. Over the limit → silently drop (no AI call, no reply) so
      # we don't feed a spam loop. Window is a rolling 10-minute bucket in the
      # shared SolidCache.
      if rate_limited?(sender)
        Rails.logger.warn("[WhatsApp Webhook] Rate limit exceeded for #{sender}; dropping message")
        respond_with_empty_twiml
        return
      end

      message = button_payload.presence || body

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
      return if Rails.env.test?
      # The rig runs RAILS_ENV=development but is reachable by Twilio over the public
      # internet, so signatures MUST be validated there. ENFORCE_TWILIO_SIGNATURE=true
      # (set in .env.rig) turns validation on in development; laptop dev stays exempt.
      return if Rails.env.development? && ENV["ENFORCE_TWILIO_SIGNATURE"] != "true"

      validator = Twilio::Security::RequestValidator.new(ENV.fetch("TWILIO_AUTH_TOKEN"))
      twilio_signature = request.headers["X-Twilio-Signature"].to_s

      # Twilio signs the EXACT public URL it posted to. Behind a tunnel/proxy the
      # host can change (e.g. a self-healing Cloudflare quick-tunnel whose subdomain
      # rotates on restart), so we don't pin a single URL: we accept the request if
      # the signature matches ANY plausible reconstruction of the public URL —
      # the configured APP_BASE_URL, the proxy-reconstructed base_url, or
      # original_url. This stays secure (the HMAC still has to match the auth token)
      # while surviving URL changes without a redeploy.
      bases = [ ENV["APP_BASE_URL"], request.base_url ].compact_blank.map { |b| b.delete_suffix("/") }
      candidates = bases.map { |b|
        u = "#{b}#{request.path}"
        request.query_string.present? ? "#{u}?#{request.query_string}" : u
      }
      candidates << request.original_url
      ok = candidates.uniq.any? { |u| validator.validate(u, request.POST, twilio_signature) }

      unless ok
        Rails.logger.warn("[WhatsApp Webhook] Invalid Twilio signature from #{request.remote_ip} (tried: #{candidates.uniq.join(' | ')})")
        head :forbidden
      end
    end

    # Max inbound messages we'll process per sender per rolling 10-minute window.
    # 40 is very generous for a real booking chat; it only catches floods/abuse.
    RATE_LIMIT_PER_10_MIN = 40

    def rate_limited?(sender)
      return false if sender.blank?

      bucket = Time.current.to_i / 600 # 10-minute window
      key = "wa_rate:#{sender}:#{bucket}"
      count = Rails.cache.increment(key, 1, expires_in: 11.minutes)
      # SolidCache returns the new count; if the store ever returns nil, fail open.
      count.present? && count > RATE_LIMIT_PER_10_MIN
    rescue StandardError => e
      Rails.logger.warn("[WhatsApp Webhook] rate_limited? error (failing open): #{e.message}")
      false
    end

    def respond_with_empty_twiml
      twiml = Twilio::TwiML::MessagingResponse.new
      render xml: twiml.to_xml, content_type: "text/xml"
    end
  end
end

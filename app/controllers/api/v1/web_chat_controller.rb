# Public website chat-widget endpoint — the SAME booking brain as WhatsApp, for the web.
# FLIP-SWITCH: OFF by default — returns 404 unless WEB_CHAT_ENABLED is truthy. Anonymous (no
# login): the widget sends a localStorage session_id that carries conversation memory. CORS is
# opened to the configured website origin(s) (WEB_CHAT_ALLOWED_ORIGINS, comma-separated).
# POPIA: WebChatService only books once a WhatsApp number + consent are provided.
class Api::V1::WebChatController < ActionController::API
  before_action :require_web_chat_enabled
  before_action :set_cors_headers

  # POST /api/v1/web_chat
  def create
    result = WebChatService.new.handle_message(
      session_id:    params[:session_id].presence || SecureRandom.uuid,
      message:       params[:message].to_s,
      visitor_name:  params[:visitor_name].presence,
      visitor_phone: params[:visitor_phone].presence,
      consent:       ActiveModel::Type::Boolean.new.cast(params[:consent])
    )
    render json: result
  rescue StandardError => e
    Rails.logger.error("[WebChat] #{e.class}: #{e.message}")
    render json: {
      reply: "Sorry — something went wrong on our side. Please try again, or WhatsApp us on +27 71 884 3204.",
      error: true
    }, status: :ok
  end

  # OPTIONS /api/v1/web_chat — CORS preflight
  def preflight
    head :no_content
  end

  private

  def require_web_chat_enabled
    head :not_found unless ActiveModel::Type::Boolean.new.cast(ENV["WEB_CHAT_ENABLED"])
  end

  def set_cors_headers
    allowed = ENV["WEB_CHAT_ALLOWED_ORIGINS"].to_s.split(",").map(&:strip)
    origin  = request.headers["Origin"].to_s
    allow   = allowed.include?(origin) ? origin : (allowed.first.presence || "*")
    response.set_header("Access-Control-Allow-Origin", allow)
    response.set_header("Access-Control-Allow-Methods", "POST, OPTIONS")
    response.set_header("Access-Control-Allow-Headers", "Content-Type, X-Widget-Session")
    response.set_header("Vary", "Origin")
  end
end

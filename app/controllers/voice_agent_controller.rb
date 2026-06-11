# Endpoints consumed by the self-hosted Pipecat VOICE agent (a separate process on the rig).
#
# SINGLE SOURCE OF TRUTH: the spoken persona + every rule comes from PromptBuilder(channel: :voice),
# which already assembles identity, SA personality, business rules, pricing, hours, public holidays,
# whitening, escalation and live availability from PracticeConfig. The Python voice agent holds NO
# hardcoded knowledge — it fetches the assembled prompt here, so changing wording in ONE place
# (PromptBuilder / config/practice_config.yml) updates both WhatsApp and voice.
#
# SAFETY: returns 404 unless VOICE_AGENT_ENABLED=true (so deploying this cannot affect live Ivory),
# and is protected by a shared bearer token (VOICE_AGENT_TOKEN). No PHI is returned by #prompt.
class VoiceAgentController < ActionController::API
  before_action :require_voice_agent_enabled
  before_action :authenticate_voice_agent

  # GET /voice_agent/prompt?language=en|af
  # Returns the assembled VOICE system prompt (the one canonical source).
  # Per-call patient/availability context is injected by the agent's tool calls later.
  def prompt
    builder = PromptBuilder.new(
      channel: :voice,
      context: { language: params[:language].presence || "en" }
    )
    render json: {
      prompt: builder.build,
      channel: "voice",
      generated_at: Time.current.iso8601
    }
  end

  private

  def require_voice_agent_enabled
    head :not_found unless ENV["VOICE_AGENT_ENABLED"] == "true"
  end

  def authenticate_voice_agent
    expected = ENV["VOICE_AGENT_TOKEN"].to_s
    provided = request.headers["Authorization"].to_s.sub(/\ABearer /, "")
    unless expected.present? && ActiveSupport::SecurityUtils.secure_compare(expected, provided)
      head :unauthorized
    end
  end
end

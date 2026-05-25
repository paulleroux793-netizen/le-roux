# N3 — Generates the end-of-appointment bullet summary that Paul
# specified on 2026-05-23: "What did the dentist say? What did the
# patient ask? What did the dentist answer? What's the estimate intent?"
#
# Inputs: an Appointment (which carries one or more ScribeSession
# transcripts via patient_id/appointment_id) + optional explicit
# scribe session.
#
# Outputs: writes `summary_decisions_text`, `summary_patient_questions`,
# `summary_estimate_intent_text`, `summary_generated_at`, and
# `summary_scribe_session_id` on the Appointment.
#
# AI provider: Anthropic Claude via the existing ruby-anthropic gem
# (already in the Gemfile). We deliberately keep the prompt prescriptive
# and ASK FOR STRICT JSON so the parser is forgiving and downstream code
# doesn't need to re-format.
#
# This is the SERVER-SIDE COMPANION to the always-on scribe (N1). It
# is invoked automatically when an appointment status transitions to
# `completed` — see AppointmentsController#set_status.

class AppointmentSummaryService
  class Error < StandardError; end

  PROMPT_SYSTEM = <<~PROMPT.freeze
    You are a clinical scribe assistant for a private South African dental practice.
    Read the transcript of a dental appointment and produce a structured summary that
    a returning patient or auditor could read in 30 seconds.

    Output STRICT JSON only, with this exact shape:
    {
      "decisions": "<single paragraph: what the dentist diagnosed, decided to do, recommended>",
      "patient_questions": [{"q": "patient's question", "a": "dentist's answer"}],
      "estimate_intent": "<one or two sentences: which procedures the dentist plans to estimate / invoice for, and any cost ranges discussed>"
    }

    Rules:
    - If the transcript contains no clear patient question, return [] for patient_questions.
    - If estimate-related discussion is absent, return an empty string for estimate_intent.
    - Never invent procedures or ICD-10 codes that weren't mentioned in the transcript.
    - Use South African English; rands not dollars.
    - Do not output anything outside the JSON object.
  PROMPT

  def self.summarise!(appointment)
    new(appointment).call
  end

  def initialize(appointment)
    @appointment = appointment
  end

  def call
    transcript = primary_transcript
    return nil if transcript.blank?

    # POPIA — never call the LLM if the patient hasn't signed consent.
    # Receptionist ticks the checkbox in the patient profile after
    # filing the paper form (Paul's 2026-05-24 decision).
    unless @appointment.patient&.ai_consent?
      Rails.logger.info("[AppointmentSummaryService] skipping — patient #{@appointment.patient_id} has no AI consent on file")
      return nil
    end

    response = anthropic_complete(transcript)
    parsed   = JSON.parse(response)

    @appointment.update!(
      summary_decisions_text:        parsed["decisions"].to_s.strip,
      summary_patient_questions:     Array(parsed["patient_questions"]).map { |h|
        { q: h["q"].to_s.strip, a: h["a"].to_s.strip }
      }.reject { |x| x[:q].blank? && x[:a].blank? },
      summary_estimate_intent_text:  parsed["estimate_intent"].to_s.strip,
      summary_scribe_session_id:     primary_session&.id,
      summary_generated_at:          Time.current
    )
    @appointment
  rescue JSON::ParserError => e
    Rails.logger.warn("[AppointmentSummaryService] non-JSON LLM output: #{e.message}")
    raise Error, "LLM returned non-JSON output"
  end

  private

  # Find the best transcript for this appointment.
  # Priority: explicit ScribeSession bound to the appointment → otherwise
  # the most recent session for this patient on the same day.
  def primary_session
    @primary_session ||= begin
      direct = ScribeSession.where(appointment_id: @appointment.id)
                            .where.not(transcript: [ nil, "" ])
                            .order(created_at: :desc).first
      direct || ScribeSession.where(patient_id: @appointment.patient_id)
                             .where.not(transcript: [ nil, "" ])
                             .where("created_at >= ?", @appointment.start_time - 30.minutes)
                             .where("created_at <= ?", @appointment.end_time   + 30.minutes)
                             .order(created_at: :desc).first
    end
  end

  def primary_transcript
    primary_session&.transcript.to_s
  end

  def anthropic_complete(transcript)
    return JSON.dump(stub_payload(transcript)) unless ENV["ANTHROPIC_API_KEY"].present?

    require "anthropic"
    client = Anthropic::Client.new(access_token: ENV["ANTHROPIC_API_KEY"])
    msg = client.messages(parameters: {
      model: ENV.fetch("ANTHROPIC_SUMMARY_MODEL", "claude-haiku-4-5-20251001"),
      max_tokens: 800,
      system: PROMPT_SYSTEM,
      messages: [ { role: "user", content: "TRANSCRIPT:\n\n#{transcript}" } ]
    })
    content = msg.dig("content", 0, "text") || msg["content"].to_s
    # Some models like to wrap JSON in ```json fences; strip them defensively.
    content.gsub(/\A```(?:json)?\s*/, "").gsub(/```\s*\z/, "")
  rescue StandardError => e
    # Dev convenience: a stale / unauthorised API key shouldn't break the
    # summary feature in demos. Log and fall back to the deterministic
    # stub so the UI can still be exercised end-to-end.
    Rails.logger.warn("[AppointmentSummaryService] LLM call failed (#{e.class}: #{e.message}); falling back to stub")
    JSON.dump(stub_payload(transcript))
  end

  # Local stub for dev when no API key is configured. Produces a
  # deterministic skeleton so the UI can be exercised end-to-end without
  # making a paid API call.
  def stub_payload(transcript)
    snippet = transcript.to_s.lines.first(2).join.strip.slice(0, 160)
    {
      decisions: snippet.presence || "[DEV STUB] Routine examination, plan to monitor.",
      patient_questions: [],
      estimate_intent: "[DEV STUB] No estimate-relevant discussion detected — set ANTHROPIC_API_KEY for real summaries."
    }
  end
end

# Always-on scribe — Phase 1 ingestion endpoint (Paul's 2026-05-24 decision).
#
# The practice-PC daemon (tools/scribe-daemon/daemon.py) records audio
# from a labelled microphone, transcribes it LOCALLY with Whisper
# (POPIA-safe — audio never leaves the practice PC), and POSTs the
# transcript text here in short chunks.
#
# What this controller does on each chunk:
#   1. Authenticates via X-Scribe-Token header (shared secret).
#   2. Stamps the RecordingDevice's last_seen_at.
#   3. Finds the "current" appointment for this device — the most recent
#      in_consultation appointment whose patient HAS AI consent on file.
#   4. Finds or creates a recording ScribeSession bound to that device +
#      appointment.
#   5. Appends the transcript_text to the session.
#
# When no in_consultation appointment matches OR the patient has no AI
# consent, the chunk is silently dropped (we log it but never write).
class Api::V1::ScribeController < ActionController::API
  before_action :authenticate_scribe!

  # POST /api/v1/scribe/transcript
  # Body (JSON):
  #   { device_name: "Surgery 1",
  #     transcript_text: "Patient says tooth 16 sensitive on cold...",
  #     chunk_started_at: "2026-05-24T10:14:30Z",
  #     chunk_ended_at:   "2026-05-24T10:15:00Z" }
  def transcript
    device = RecordingDevice.enabled.find_by(name: params[:device_name].to_s)
    unless device
      return render json: { ok: false, reason: "unknown_device" }, status: :not_found
    end
    device.touch(:last_seen_at)

    text = params[:transcript_text].to_s.strip
    return render json: { ok: true, accepted: false, reason: "empty" } if text.empty?

    appointment = current_appointment_for(device)
    unless appointment
      Rails.logger.info("[scribe] dropping chunk from #{device.name}: no in_consultation appointment with AI consent")
      return render json: { ok: true, accepted: false, reason: "no_active_appointment_with_consent" }
    end

    session = ScribeSession.where(appointment_id: appointment.id, status: "recording")
                           .order(created_at: :desc).first
    session ||= ScribeSession.create!(
      patient_id: appointment.patient_id,
      appointment_id: appointment.id,
      recording_device_id: device.id,
      status: "recording",
      started_at: Time.current
    )

    # Append, never overwrite. Whisper chunks come in 5–30 second bursts;
    # one ScribeSession ends up holding the full conversation transcript.
    session.update!(transcript: [ session.transcript, text ].compact.reject(&:blank?).join("\n"))

    render json: { ok: true, accepted: true, scribe_session_id: session.id, appointment_id: appointment.id }
  end

  # GET /api/v1/scribe/heartbeat
  # The daemon calls this every 60s so we know it's alive even if the
  # surgery is quiet (no transcript to send). Updates last_seen_at.
  def heartbeat
    device = RecordingDevice.find_by(name: params[:device_name].to_s)
    if device
      device.touch(:last_seen_at)
      render json: { ok: true, device_id: device.id, enabled: device.enabled }
    else
      render json: { ok: false, reason: "unknown_device" }, status: :not_found
    end
  end

  private

  def authenticate_scribe!
    expected = ENV["SCRIBE_API_TOKEN"].to_s
    if expected.blank?
      render json: { ok: false, reason: "scribe_disabled_no_token_configured" }, status: :service_unavailable
      return
    end
    presented = request.headers["X-Scribe-Token"].to_s
    if !ActiveSupport::SecurityUtils.secure_compare(expected, presented)
      render json: { ok: false, reason: "unauthorised" }, status: :unauthorized
    end
  end

  # The "current" appointment for a device:
  # most recent in_consultation appointment whose patient has AI consent
  # AND whose start_time is within the last 4 hours (so a forgotten
  # in_consultation appointment from yesterday doesn't catch today's audio).
  def current_appointment_for(_device)
    Appointment.joins(:patient)
               .where(status: :in_consultation)
               .where("appointments.start_time >= ?", 4.hours.ago)
               .where.not(patients: { consent_to_ai_processing_at: nil })
               .order(start_time: :desc)
               .first
  end
end

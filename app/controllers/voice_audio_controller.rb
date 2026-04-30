# Public endpoint Twilio fetches via TwiML <Play> to get the AI-generated
# audio for the current voice turn. Audio is generated and cached by
# ElevenLabsService keyed on SHA256 of (text + voice_id + model_id);
# this controller only serves cached blobs and never generates.
#
# Twilio sends GETs from many IPs without auth. Rails doesn't CSRF-protect
# GETs, but we explicitly skip the verify_authenticity_token callback in
# case ApplicationController grows new before_actions.
class VoiceAudioController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false

  HASH_REGEX = /\A[a-f0-9]{64}\z/

  def show
    hash = params[:hash].to_s

    return head :not_found unless hash.match?(HASH_REGEX)

    audio = ElevenLabsService.new.cached_audio(hash)
    return head :not_found if audio.blank?

    send_data audio,
      type: "audio/mpeg",
      disposition: "inline",
      filename: "#{hash}.mp3"
  end
end

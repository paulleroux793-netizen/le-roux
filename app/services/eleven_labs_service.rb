require "net/http"
require "json"
require "digest"

# Generates and caches MP3 audio from ElevenLabs Text-to-Speech for use
# by VoiceService inside TwiML <Play> elements.
#
# The voice agent pipes AI-generated text through this service to obtain
# a public MP3 URL Twilio fetches and plays to the patient. Cached by
# SHA256(text + voice_id + model_id) in Rails.cache (Solid Cache on
# Railway), so repeated phrases — greetings, common FAQ replies, the
# whitening info block — only hit the ElevenLabs API once.
#
# Failure-tolerant: if ElevenLabs is unconfigured, unreachable, or
# returns an error, `audio_url_for` returns nil. VoiceService treats nil
# as "fall back to Polly Joanna via <Say>" so the call still completes.
# The patient hears a worse voice rather than a broken call.
class ElevenLabsService
  class Error < StandardError; end

  API_BASE = "https://api.elevenlabs.io/v1".freeze
  CACHE_NAMESPACE = "voice_audio".freeze
  CACHE_TTL = 30.days
  HTTP_READ_TIMEOUT = 30
  DEFAULT_MODEL_ID = "eleven_multilingual_v2".freeze
  HASH_REGEX = /\A[a-f0-9]{64}\z/

  # Returns the public URL of a cached MP3 of `text`. Generates and caches
  # if not already cached. Returns nil if ElevenLabs is unconfigured, the
  # text is blank, or the API call fails — caller (VoiceService) falls
  # back to Polly via <Say>.
  def audio_url_for(text)
    return nil unless configured?
    return nil if text.blank?

    hash = digest(text)

    bytes = begin
      Rails.cache.fetch(cache_key(hash), expires_in: CACHE_TTL) do
        generate_mp3(text)
      end
    rescue Error => e
      Rails.logger.warn("[ElevenLabs] generation failed for text='#{text.to_s[0..60]}': #{e.message}")
      nil
    end

    return nil if bytes.blank?

    "#{base_url}/voice/audio/#{hash}.mp3"
  end

  # Returns cached MP3 bytes for `hash`, or nil if not cached.
  # VoiceAudioController uses this to serve audio to Twilio.
  def cached_audio(hash)
    return nil unless hash.to_s.match?(HASH_REGEX)

    Rails.cache.read(cache_key(hash))
  end

  private

  def configured?
    api_key.present? && voice_id.present?
  end

  def api_key
    ENV["ELEVENLABS_API_KEY"]
  end

  def voice_id
    ENV["ELEVENLABS_VOICE_ID"]
  end

  def model_id
    ENV.fetch("ELEVENLABS_MODEL_ID", DEFAULT_MODEL_ID)
  end

  def base_url
    ENV.fetch("APP_BASE_URL", "http://localhost:3000")
  end

  def cache_key(hash)
    "#{CACHE_NAMESPACE}:#{hash}"
  end

  # Includes voice_id + model_id so swapping either invalidates the
  # cache automatically — old MP3s aren't served after a voice change.
  def digest(text)
    Digest::SHA256.hexdigest("#{text}|#{voice_id}|#{model_id}")
  end

  def generate_mp3(text)
    uri = URI("#{API_BASE}/text-to-speech/#{voice_id}")
    request = Net::HTTP::Post.new(uri)
    request["xi-api-key"] = api_key
    request["accept"] = "audio/mpeg"
    request["content-type"] = "application/json"
    request.body = {
      text: text,
      model_id: model_id,
      voice_settings: { stability: 0.5, similarity_boost: 0.75 }
    }.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.read_timeout = HTTP_READ_TIMEOUT
      http.request(request)
    end

    unless response.code == "200"
      raise Error, "HTTP #{response.code}: #{response.body.to_s[0..200]}"
    end

    response.body.force_encoding("ASCII-8BIT")
  rescue Net::ReadTimeout, Errno::ECONNREFUSED, SocketError => e
    raise Error, "network: #{e.class}: #{e.message}"
  end
end

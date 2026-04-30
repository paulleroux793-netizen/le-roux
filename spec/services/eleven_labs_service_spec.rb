require "rails_helper"

RSpec.describe ElevenLabsService do
  let(:voice_id) { "x8syuETaTA9JYwAbE2JM" }
  let(:api_key)  { "test_api_key" }
  let(:model_id) { "eleven_multilingual_v2" }
  let(:base_url) { "https://test.ngrok.io" }
  let(:text)     { "Hello, you've reached the practice." }
  let(:fake_mp3) { "FAKE_MP3_BYTES".b }

  let(:tts_endpoint) { "https://api.elevenlabs.io/v1/text-to-speech/#{voice_id}" }

  before do
    stub_const(
      "ENV",
      ENV.to_h.merge(
        "ELEVENLABS_API_KEY"  => api_key,
        "ELEVENLABS_VOICE_ID" => voice_id,
        "ELEVENLABS_MODEL_ID" => model_id,
        "APP_BASE_URL"        => base_url
      )
    )
    Rails.cache.clear
  end

  let(:service) { described_class.new }

  describe "#audio_url_for" do
    context "when ElevenLabs returns success" do
      before do
        stub_request(:post, tts_endpoint)
          .to_return(status: 200, body: fake_mp3, headers: { "Content-Type" => "audio/mpeg" })
      end

      it "returns a public URL with a 64-char SHA256 hash and .mp3 suffix" do
        url = service.audio_url_for(text)

        expect(url).to start_with("#{base_url}/voice/audio/")
        expect(url).to end_with(".mp3")
        expect(url).to match(%r{\A#{Regexp.escape(base_url)}/voice/audio/[a-f0-9]{64}\.mp3\z})
      end

      it "caches the bytes — a second call does not hit the API" do
        service.audio_url_for(text)
        service.audio_url_for(text)

        expect(WebMock).to have_requested(:post, tts_endpoint).once
      end

      it "stores cached bytes retrievable via cached_audio(hash)" do
        url = service.audio_url_for(text)
        hash = url[%r{/([a-f0-9]{64})\.mp3\z}, 1]

        expect(service.cached_audio(hash)).to eq(fake_mp3)
      end

      it "POSTs the expected JSON body to ElevenLabs" do
        service.audio_url_for(text)

        expect(WebMock).to have_requested(:post, tts_endpoint).with { |req|
          parsed = JSON.parse(req.body)
          parsed["text"] == text &&
            parsed["model_id"] == model_id &&
            parsed["voice_settings"].is_a?(Hash)
        }
      end

      it "sends the xi-api-key header" do
        service.audio_url_for(text)

        expect(WebMock).to have_requested(:post, tts_endpoint)
          .with(headers: { "xi-api-key" => api_key })
      end
    end

    context "when ElevenLabs returns 5xx" do
      before do
        stub_request(:post, tts_endpoint).to_return(status: 500, body: "server error")
      end

      it "returns nil so caller can fall back to Polly" do
        expect(service.audio_url_for(text)).to be_nil
      end

      it "does not cache an error response" do
        service.audio_url_for(text)
        # Cache should remain empty so subsequent calls retry the API.
        expect(Rails.cache.read("voice_audio:any")).to be_nil
      end
    end

    context "when ElevenLabs returns 401" do
      before do
        stub_request(:post, tts_endpoint).to_return(status: 401, body: "invalid key")
      end

      it "returns nil rather than raising" do
        expect { service.audio_url_for(text) }.not_to raise_error
        expect(service.audio_url_for(text)).to be_nil
      end
    end

    context "when API key is missing" do
      before do
        stub_const("ENV", ENV.to_h.merge("ELEVENLABS_API_KEY" => nil))
      end

      it "returns nil without calling the API" do
        expect(service.audio_url_for(text)).to be_nil
      end

      it "does not make any HTTP request" do
        service.audio_url_for(text)
        expect(WebMock).not_to have_requested(:post, tts_endpoint)
      end
    end

    context "when voice_id is missing" do
      before do
        stub_const("ENV", ENV.to_h.merge("ELEVENLABS_VOICE_ID" => nil))
      end

      it "returns nil" do
        expect(service.audio_url_for(text)).to be_nil
      end
    end

    context "when text is blank" do
      before do
        stub_request(:post, tts_endpoint)
          .to_return(status: 200, body: fake_mp3, headers: { "Content-Type" => "audio/mpeg" })
      end

      it "returns nil for empty string" do
        expect(service.audio_url_for("")).to be_nil
      end

      it "returns nil for nil" do
        expect(service.audio_url_for(nil)).to be_nil
      end

      it "does not call the API" do
        service.audio_url_for("")
        service.audio_url_for(nil)
        expect(WebMock).not_to have_requested(:post, tts_endpoint)
      end
    end

    context "cache invalidation" do
      before do
        stub_request(:post, tts_endpoint)
          .to_return(status: 200, body: fake_mp3, headers: { "Content-Type" => "audio/mpeg" })
      end

      it "produces a different hash when voice_id changes" do
        url1 = service.audio_url_for(text)
        stub_const("ENV", ENV.to_h.merge("ELEVENLABS_VOICE_ID" => "different_voice"))
        url2 = described_class.new.audio_url_for(text)

        expect(url1).not_to eq(url2)
      end

      it "produces a different hash when model_id changes" do
        url1 = service.audio_url_for(text)
        stub_const("ENV", ENV.to_h.merge("ELEVENLABS_MODEL_ID" => "eleven_turbo_v2"))
        url2 = described_class.new.audio_url_for(text)

        expect(url1).not_to eq(url2)
      end

      it "produces a different hash when text changes" do
        url1 = service.audio_url_for("Hello")
        url2 = service.audio_url_for("Goodbye")

        expect(url1).not_to eq(url2)
      end
    end
  end

  describe "#cached_audio" do
    it "returns nil for an invalid hash format" do
      expect(service.cached_audio("not_a_hash")).to be_nil
      expect(service.cached_audio("")).to be_nil
      expect(service.cached_audio(nil)).to be_nil
    end

    it "returns nil for a valid-format hash that isn't cached" do
      sha = "a" * 64
      expect(service.cached_audio(sha)).to be_nil
    end

    it "returns the cached bytes when present" do
      stub_request(:post, tts_endpoint)
        .to_return(status: 200, body: fake_mp3, headers: { "Content-Type" => "audio/mpeg" })

      url = service.audio_url_for(text)
      hash = url[%r{/([a-f0-9]{64})\.mp3\z}, 1]

      expect(service.cached_audio(hash)).to eq(fake_mp3)
    end
  end
end

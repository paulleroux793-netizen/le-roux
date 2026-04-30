require "rails_helper"

RSpec.describe "Voice audio endpoint", type: :request do
  let(:valid_hash) { "a" * 64 } # 64 hex chars
  let(:fake_mp3)   { "FAKE_MP3_BYTES".b }

  before { Rails.cache.clear }

  describe "GET /voice/audio/:hash.mp3" do
    context "when audio is cached" do
      before do
        Rails.cache.write("voice_audio:#{valid_hash}", fake_mp3, expires_in: 30.days)
      end

      it "returns 200 with audio/basic content type (Twilio-native μ-law 8kHz)" do
        get "/voice/audio/#{valid_hash}.mp3"

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to start_with("audio/basic")
      end

      it "returns the cached MP3 bytes" do
        get "/voice/audio/#{valid_hash}.mp3"

        expect(response.body.b).to eq(fake_mp3)
      end
    end

    context "when audio is NOT cached" do
      it "returns 404" do
        get "/voice/audio/#{valid_hash}.mp3"

        expect(response).to have_http_status(:not_found)
      end
    end

    context "when hash is the wrong format (path-traversal defence)" do
      it "returns 404 for short hash" do
        get "/voice/audio/abc.mp3"

        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 for hash containing uppercase / non-hex chars" do
        get "/voice/audio/#{'A' * 64}.mp3"

        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 for hash with traversal characters" do
        get "/voice/audio/..%2Fconfig%2Fmaster_key.mp3"

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end

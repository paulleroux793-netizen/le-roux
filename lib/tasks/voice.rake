namespace :voice do
  desc "Pre-generate ElevenLabs MP3 audio for constant voice prompts so first-call latency is low."
  task warm_cache: :environment do
    service = ElevenLabsService.new

    constants = [
      [ "GREETING",        VoiceService::GREETING ],
      [ "NO_SPEECH_REPLY", VoiceService::NO_SPEECH_REPLY ],
      [ "GOODBYE_REPLY",   VoiceService::GOODBYE_REPLY ]
    ]

    constants.each do |name, text|
      url = service.audio_url_for(text)
      if url
        puts "OK   #{name}: #{url}"
      else
        puts "FAIL #{name}: ElevenLabs unconfigured or API failed (check ELEVENLABS_API_KEY + ELEVENLABS_VOICE_ID)"
      end
    end
  end
end

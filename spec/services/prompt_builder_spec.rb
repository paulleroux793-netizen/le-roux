require "rails_helper"

RSpec.describe PromptBuilder do
  before do
    # Stub DoctorSchedule lookup so the prompt's working_hours_block falls
    # back to its hardcoded values; keeps the spec fast and DB-independent.
    allow(DoctorSchedule).to receive(:order).and_return([])
    allow(DoctorSchedule).to receive(:for_day).and_return(nil)
  end

  describe "channel parameter" do
    it "defaults to :whatsapp when no channel is given" do
      builder = described_class.new
      expect(builder.instance_variable_get(:@channel)).to eq(:whatsapp)
    end

    it "stores :whatsapp when passed explicitly" do
      builder = described_class.new(channel: :whatsapp)
      expect(builder.instance_variable_get(:@channel)).to eq(:whatsapp)
    end

    it "stores :voice when passed explicitly" do
      builder = described_class.new(channel: :voice)
      expect(builder.instance_variable_get(:@channel)).to eq(:voice)
    end

    it "normalises a string channel into a symbol" do
      builder = described_class.new(channel: "voice")
      expect(builder.instance_variable_get(:@channel)).to eq(:voice)
    end

    it "exposes the recognised channels via CHANNELS constant" do
      expect(described_class::CHANNELS).to eq(%i[whatsapp voice])
    end
  end

  describe "#build (PR 1 invariant — output is byte-identical across channels)" do
    # The PR that introduces this parameter intentionally produces the SAME
    # prompt for every channel. Voice-specific format rules + identity ship
    # in a follow-up PR (Phase 9.16). These assertions guard against the
    # refactor accidentally diverging the two channels before PR 2 lands.

    it "produces identical output for :whatsapp and :voice" do
      whatsapp_prompt = described_class.new(channel: :whatsapp).build
      voice_prompt    = described_class.new(channel: :voice).build
      expect(voice_prompt).to eq(whatsapp_prompt)
    end

    it "produces identical output between the default and an explicit :whatsapp" do
      default_prompt  = described_class.new.build
      whatsapp_prompt = described_class.new(channel: :whatsapp).build
      expect(default_prompt).to eq(whatsapp_prompt)
    end

    it "still contains the WhatsApp identity line on the voice channel (will flip in PR 2)" do
      voice_prompt = described_class.new(channel: :voice).build
      expect(voice_prompt).to include("WhatsApp booking assistant")
    end

    it "still contains the WhatsApp format-rules section on the voice channel (will flip in PR 2)" do
      voice_prompt = described_class.new(channel: :voice).build
      expect(voice_prompt).to include("CRITICAL MESSAGE-FORMAT RULES")
    end
  end
end

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

  describe "#build — channel divergence (Phase 9.19.3)" do
    let(:whatsapp_prompt) { described_class.new(channel: :whatsapp).build }
    let(:voice_prompt)    { described_class.new(channel: :voice).build }
    let(:default_prompt)  { described_class.new.build }

    describe "default channel preserves WhatsApp behaviour" do
      it "default and explicit :whatsapp produce identical output" do
        expect(default_prompt).to eq(whatsapp_prompt)
      end

      it "default channel contains the WhatsApp identity line" do
        expect(default_prompt).to include("WhatsApp booking assistant")
      end

      it "default channel contains the WhatsApp format rules with asterisks" do
        expect(default_prompt).to include("Use *asterisks* for bold")
      end
    end

    describe ":whatsapp channel (regression — must not silently change)" do
      it "identifies as the WhatsApp booking assistant" do
        expect(whatsapp_prompt).to include("WhatsApp booking assistant")
      end

      it "instructs the AI to use a numbered list for booking info" do
        expect(whatsapp_prompt).to include("WhatsApp-native numbered list")
      end

      it "permits markdown asterisks for bold" do
        expect(whatsapp_prompt).to include("Use *asterisks* for bold")
      end

      it "shows numbered slot examples like '1. *09:30*'" do
        expect(whatsapp_prompt).to match(/\b1\.\s+\*\d{2}:\d{2}\*/)
      end

      it "still contains the 2-3 sentences max for WhatsApp guidance" do
        expect(whatsapp_prompt).to include("2-3 sentences max for WhatsApp")
      end
    end

    describe ":voice channel — diverges from WhatsApp" do
      it "identifies as the voice receptionist, not the WhatsApp assistant" do
        expect(voice_prompt).to include("voice receptionist")
        expect(voice_prompt).not_to include("WhatsApp booking assistant")
      end

      it "tells the AI it is being read aloud by TTS" do
        expect(voice_prompt).to include("read aloud by a text-to-speech engine")
      end

      it "forbids markdown — TTS would pronounce 'asterisk'" do
        expect(voice_prompt).to include("NO markdown of any kind")
        expect(voice_prompt).to include("literally pronounces these characters")
      end

      it "does NOT include the numbered-list booking-form template" do
        expect(voice_prompt).not_to include("WhatsApp-native numbered list")
      end

      it "does NOT instruct the AI to use *asterisks* for bold" do
        expect(voice_prompt).not_to include("Use *asterisks* for bold")
      end

      it "does NOT include the WhatsApp '*09:30*' slot-format example" do
        expect(voice_prompt).not_to match(/\b1\.\s+\*\d{2}:\d{2}\*/)
      end

      it "instructs one question per turn instead of a numbered booking ask" do
        expect(voice_prompt).to include("One question per turn")
      end

      it "uses spoken-language slot examples like 'half past nine'" do
        expect(voice_prompt).to include("half past nine in the morning")
      end

      it "references the SA reception phrasing from the call corpus" do
        expect(voice_prompt).to include("Michelle and Liska")
        expect(voice_prompt).to include("shame")
      end

      it "covers the spell-back-of-names rule" do
        expect(voice_prompt).to include("Spell back the patient's name")
      end

      it "covers the walk-in handling" do
        expect(voice_prompt).to include("don't take walk-ins")
      end
    end

    describe "shared business rules — must appear in BOTH channels" do
      # Anti-drift assertions: pricing, hours, public holidays, whitening,
      # weekend rules, escalation, surgical-extraction redirect — these are
      # clinic policy, not channel format. They must stay shared.

      %i[whatsapp voice].each do |channel|
        context "channel = #{channel}" do
          let(:prompt) { described_class.new(channel: channel).build }

          it "includes the working hours rule" do
            expect(prompt).to include("Monday to Friday")
            expect(prompt).to include("CLOSED")
          end

          it "includes the whitening flow with R7,800 + R2,000 deposit" do
            expect(prompt).to include("R7,800")
            expect(prompt).to include("R2,000 deposit")
          end

          it "includes the public-holidays list" do
            expect(prompt).to include("public holiday")
          end

          it "includes the consultation pricing fallback (R850)" do
            expect(prompt).to include("R850")
          end

          it "includes the practice address override (Roodepoort, NOT Pretoria)" do
            expect(prompt).to include("Roodepoort")
            expect(prompt).to include("NEVER say \"Pretoria\"")
          end

          it "includes the surgical-extraction refer-out rule" do
            expect(prompt).to include("SERVICES WE DO NOT OFFER")
            expect(prompt).to include("Surgical extractions")
            expect(prompt).to include("oral surgeon")
            expect(prompt).to include("don't perform surgical extractions in-house")
          end

          it "includes the orthodontics-beyond-aligners refer-out rule" do
            expect(prompt).to include("Orthodontic work beyond clear aligners")
            expect(prompt).to include("orthodontist")
          end

          it "lists trigger phrases the AI must catch for surgical/orthodontics" do
            expect(prompt).to include("surgical extraction")
            expect(prompt).to include("impacted tooth")
            expect(prompt).to include("wisdom tooth surgery")
          end

          it "still allows in-house standard extractions to book normally" do
            expect(prompt).to include("Standard extractions")
            expect(prompt).to include("ARE done in-house")
          end
        end
      end
    end
  end
end

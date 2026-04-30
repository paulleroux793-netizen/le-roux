require "rails_helper"

RSpec.describe VoiceService do
  let(:service)    { described_class.new }
  let(:ai_service) { instance_double(AiService) }
  let(:eleven_labs) { instance_double(ElevenLabsService, audio_url_for: nil) }

  before do
    allow(AiService).to receive(:new).and_return(ai_service)
    # ElevenLabs default to "unconfigured / unavailable" in tests so
    # play_or_say falls back to Polly <Say> — keeps the spoken text
    # inspectable in the TwiML XML for assertions below.
    allow(ElevenLabsService).to receive(:new).and_return(eleven_labs)
    stub_const("ENV", ENV.to_h.merge("APP_BASE_URL" => "https://test.ngrok.io"))
  end

  # ── handle_incoming ───────────────────────────────────────────────────

  describe "#handle_incoming" do
    it "creates a patient from the caller number" do
      expect {
        service.handle_incoming(call_sid: "CA_001", caller: "+27821111111")
      }.to change(Patient, :count).by(1)

      patient = Patient.find_by(phone: "+27821111111")
      expect(patient).to be_present
      expect(patient.first_name).to eq("Phone")
    end

    it "reuses an existing patient" do
      create(:patient, phone: "+27821111111")

      expect {
        service.handle_incoming(call_sid: "CA_001", caller: "+27821111111")
      }.not_to change(Patient, :count)
    end

    it "creates a voice conversation for the patient" do
      expect {
        service.handle_incoming(call_sid: "CA_001", caller: "+27821111112")
      }.to change(Conversation, :count).by(1)

      conversation = Conversation.last
      expect(conversation.channel).to eq("voice")
      expect(conversation.status).to eq("active")
    end

    it "creates a call log" do
      expect {
        service.handle_incoming(call_sid: "CA_001", caller: "+27821111113")
      }.to change(CallLog, :count).by(1)

      log = CallLog.find_by(twilio_call_sid: "CA_001")
      expect(log.caller_number).to eq("+27821111113")
      expect(log.status).to eq("in-progress")
    end

    it "returns TwiML with a Gather element" do
      twiml = service.handle_incoming(call_sid: "CA_001", caller: "+27821111114")

      expect(twiml).to include("<Gather")
      expect(twiml).to include("speech")
      expect(twiml).to include("/webhooks/voice/gather")
    end

    it "returns TwiML with the greeting message" do
      twiml = service.handle_incoming(call_sid: "CA_001", caller: "+27821111115")

      expect(twiml).to include("Dr Chalita le Roux")
    end
  end

  # ── handle_gather ─────────────────────────────────────────────────────

  describe "#handle_gather" do
    let!(:patient)      { create(:patient, phone: "+27822222222") }
    let!(:conversation) { create(:conversation, patient: patient, channel: "voice", status: "active") }
    let!(:call_log) do
      CallLog.create!(
        twilio_call_sid: "CA_002",
        caller_number:   patient.phone,
        patient:         patient,
        status:          "in-progress"
      )
    end

    before do
      allow(ai_service).to receive(:process_message).and_return({
        response: "I'd be happy to help you book an appointment.",
        intent:   "book",
        entities: {}
      })
    end

    it "processes speech through AI and returns a Gather TwiML loop" do
      twiml = service.handle_gather(
        call_sid:      "CA_002",
        speech_result: "I want to book",
        confidence:    0.9
      )

      expect(ai_service).to have_received(:process_message).with(
        hash_including(message: "I want to book", patient: patient)
      )
      expect(twiml).to include("<Gather")
      expect(twiml).to include("book an appointment")
    end

    it "updates the call log with intent and AI response" do
      service.handle_gather(
        call_sid:      "CA_002",
        speech_result: "I want to book",
        confidence:    0.9
      )

      call_log.reload
      expect(call_log.intent).to eq("book")
      expect(call_log.ai_response).to include("book an appointment")
    end

    it "prompts again when speech_result is blank" do
      twiml = service.handle_gather(
        call_sid:      "CA_002",
        speech_result: "",
        confidence:    0.9
      )

      expect(ai_service).not_to have_received(:process_message)
      expect(twiml).to include("didn't catch that")
    end

    it "prompts again when confidence is below threshold" do
      twiml = service.handle_gather(
        call_sid:      "CA_002",
        speech_result: "mumble",
        confidence:    0.1
      )

      expect(ai_service).not_to have_received(:process_message)
    end

    it "returns farewell TwiML when goodbye is detected" do
      allow(ai_service).to receive(:process_message).and_return({
        response: "Have a great day!",
        intent:   "other",
        entities: {}
      })

      twiml = service.handle_gather(
        call_sid:      "CA_002",
        speech_result: "thank you goodbye",
        confidence:    0.95
      )

      # Farewell TwiML uses GOODBYE_REPLY ("Thanks for calling…") — match
      # on the warm-sign-off content rather than a literal "Goodbye" word
      # so the spec survives future tone tweaks to GOODBYE_REPLY.
      expect(twiml).to match(/Thanks for calling|lovely day|bye/i)
      expect(twiml).to include("<Hangup")
    end

    context "when AI is unavailable" do
      before do
        allow(ai_service).to receive(:process_message)
          .and_raise(AiService::Error, "timeout")
      end

      it "returns a fallback TwiML without raising" do
        twiml = service.handle_gather(
          call_sid:      "CA_002",
          speech_result: "book appointment",
          confidence:    0.9
        )

        expect(twiml).to include("<Response>")
        expect(twiml).to include("trouble")
      end
    end
  end

  # ── handle_status ─────────────────────────────────────────────────────

  describe "#handle_status" do
    let!(:patient) { create(:patient, phone: "+27823333333") }
    let!(:conversation) { create(:conversation, patient: patient, channel: "voice", status: "active") }
    let!(:call_log) do
      CallLog.create!(
        twilio_call_sid: "CA_003",
        caller_number:   patient.phone,
        patient:         patient,
        status:          "in-progress"
      )
    end

    it "updates the call log status and duration" do
      service.handle_status(call_sid: "CA_003", call_status: "completed", duration: 120)

      call_log.reload
      expect(call_log.status).to eq("completed")
      expect(call_log.duration).to eq(120)
    end

    it "closes the active voice conversation when call ends" do
      service.handle_status(call_sid: "CA_003", call_status: "completed", duration: 60)

      conversation.reload
      expect(conversation.status).to eq("closed")
    end

    it "closes conversation for no-answer calls" do
      service.handle_status(call_sid: "CA_003", call_status: "no-answer", duration: 0)

      conversation.reload
      expect(conversation.status).to eq("closed")
    end

    it "does nothing gracefully when call_sid is not found" do
      expect {
        service.handle_status(call_sid: "CA_unknown", call_status: "completed", duration: 0)
      }.not_to raise_error
    end
  end

  # ── confirmation_twiml ────────────────────────────────────────────────

  describe "#confirmation_twiml" do
    let(:patient)     { create(:patient, first_name: "Sarah") }
    let(:appointment) do
      create(:appointment, patient: patient,
        start_time: Time.zone.parse("2026-04-20 09:00"),
        end_time:   Time.zone.parse("2026-04-20 09:30"))
    end

    it "includes the patient name in the TwiML" do
      twiml = service.confirmation_twiml(appointment)

      expect(twiml).to include("Sarah")
    end

    it "includes the appointment date and time" do
      twiml = service.confirmation_twiml(appointment)

      expect(twiml).to include("April 20")
      expect(twiml).to include("09:00")
    end

    it "uses DTMF input with a Gather element" do
      twiml = service.confirmation_twiml(appointment)

      expect(twiml).to include("dtmf")
      expect(twiml).to include("<Gather")
    end

    it "includes Press 1 / press 2 / press 3 instructions" do
      twiml = service.confirmation_twiml(appointment)

      expect(twiml).to include("Press 1")
      expect(twiml).to include("press 2")
      expect(twiml).to include("press 3")
    end

    it "returns graceful TwiML when appointment is nil" do
      twiml = service.confirmation_twiml(nil)

      expect(twiml).to include("disregard")
      expect(twiml).to include("<Hangup")
    end
  end

  # ── handle_confirmation_gather ────────────────────────────────────────

  describe "#handle_confirmation_gather" do
    let(:patient)     { create(:patient) }
    let(:appointment) { create(:appointment, patient: patient, status: :scheduled) }
    let!(:log) do
      create(:confirmation_log, appointment: appointment, method: "voice", outcome: nil, flagged: false)
    end

    context "when patient presses 1 (confirm)" do
      it "marks appointment as confirmed" do
        service.handle_confirmation_gather(
          call_sid: "CA_004", digits: "1", appointment_id: appointment.id.to_s
        )

        expect(appointment.reload.status).to eq("confirmed")
      end

      it "updates the confirmation log as confirmed" do
        service.handle_confirmation_gather(
          call_sid: "CA_004", digits: "1", appointment_id: appointment.id.to_s
        )

        expect(log.reload.outcome).to eq("confirmed")
        expect(log.reload.flagged).to be(false)
      end

      it "returns a thank-you TwiML with Hangup" do
        twiml = service.handle_confirmation_gather(
          call_sid: "CA_004", digits: "1", appointment_id: appointment.id.to_s
        )

        expect(twiml).to include("confirmed")
        expect(twiml).to include("<Hangup")
      end
    end

    context "when patient presses 2 (reschedule)" do
      it "flags the confirmation log for follow-up" do
        service.handle_confirmation_gather(
          call_sid: "CA_004", digits: "2", appointment_id: appointment.id.to_s
        )

        expect(log.reload.outcome).to eq("rescheduled")
        expect(log.reload.flagged).to be(true)
      end

      it "does not cancel the appointment" do
        service.handle_confirmation_gather(
          call_sid: "CA_004", digits: "2", appointment_id: appointment.id.to_s
        )

        expect(appointment.reload.status).to eq("scheduled")
      end
    end

    context "when patient presses 3 (cancel)" do
      it "cancels the appointment" do
        service.handle_confirmation_gather(
          call_sid: "CA_004", digits: "3", appointment_id: appointment.id.to_s
        )

        expect(appointment.reload.status).to eq("cancelled")
      end

      it "flags the confirmation log" do
        service.handle_confirmation_gather(
          call_sid: "CA_004", digits: "3", appointment_id: appointment.id.to_s
        )

        expect(log.reload.outcome).to eq("cancelled")
        expect(log.reload.flagged).to be(true)
      end
    end

    context "when patient presses an unexpected digit" do
      it "flags as unclear" do
        service.handle_confirmation_gather(
          call_sid: "CA_004", digits: "9", appointment_id: appointment.id.to_s
        )

        expect(log.reload.outcome).to eq("unclear")
        expect(log.reload.flagged).to be(true)
      end
    end

    context "when appointment is not found" do
      it "returns graceful TwiML without raising" do
        twiml = service.handle_confirmation_gather(
          call_sid: "CA_004", digits: "1", appointment_id: "999999"
        )

        expect(twiml).to include("<Response>")
        expect(twiml).to include("<Hangup")
      end
    end
  end

  # ── ElevenLabs preferred path ─────────────────────────────────────────
  #
  # When ElevenLabs returns a usable audio URL, TwiML emits <Play> with
  # that URL instead of <Say> with Polly. Polly is the fallback only.

  describe "#handle_incoming with ElevenLabs configured" do
    let(:eleven_labs) do
      instance_double(
        ElevenLabsService,
        audio_url_for: "https://test.ngrok.io/voice/audio/abc.mp3"
      )
    end

    it "emits <Play> pointing at the ElevenLabs cache, not <Say>" do
      twiml = service.handle_incoming(call_sid: "CA_eleven_1", caller: "+27821234567")

      expect(twiml).to include("<Play")
      expect(twiml).to include("/voice/audio/")
      expect(twiml).not_to include("<Say")
    end
  end

  describe "Polly fallback when ElevenLabs is unavailable" do
    # Default before-block stubs eleven_labs.audio_url_for to nil — every
    # test above this section is implicitly exercising the Polly fallback
    # path, but this test makes the contract explicit so a future ElevenLabs
    # refactor can't silently regress it.

    it "emits TwiML <Say> with Polly Joanna voice when audio_url_for returns nil" do
      twiml = service.handle_incoming(call_sid: "CA_polly_1", caller: "+27829999999")

      expect(twiml).to include("<Say")
      expect(twiml).to include("Polly.Joanna")
      expect(twiml).not_to include("<Play")
    end
  end
end
